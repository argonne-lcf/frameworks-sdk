#!/usr/bin/env bash
#
# prepare_requirements.sh -- split a pinned requirements list against a wheel directory.
#
# Replaces the force_wheelfiles.sh + remove_wheels.sh pair with a single pass that
# knows about the wheel directory, so it cannot silently emit an empty wheel list.
#
# Usage:
#   ./prepare_requirements.sh [options] <wheel_dir> <list_file>
#
# Given a directory of locally built wheels and a pinned list (one name==version per
# line, e.g. RC4_all.list), emits three files next to <list_file>:
#
#   <stem>_nowheels.list   entries with no matching wheel
#                          -> pip install --no-deps --no-index -r <stem>_nowheels.list
#   <stem>_wheels.list     paths to the matching wheels
#                          -> pip install --no-deps -r <stem>_wheels.list
#   <stem>_report.txt      matches, version mismatches, duplicates, unmatched wheels
#
# Matching is by PEP 503 normalized name (runs of [-_.] -> "-", lowercased), so
# scikit-learn-intelex matches scikit_learn_intelex-*.whl. Versions are compared, and
# a disagreement is reported loudly rather than silently substituted.
#
# Options:
#   -o, --outdir DIR       write outputs to DIR (default: alongside <list_file>)
#       --rel              write wheel paths as given instead of absolute. pip resolves
#                          them against the CWD, not the list file, so only use this if
#                          you always run pip from the same directory.
#       --allow-mismatch   version mismatches are informational, not exit-2
#       --no-metadata-check  trust wheel filenames; skip reading dist-info METADATA
#   -n, --dry-run          report to stdout only; write nothing
#   -h, --help             this message
#
# Exit codes:
#   0  clean
#   1  usage or fatal error
#   2  completed, but with problems needing a human decision
#
# Requires bash 3.2+ (no associative arrays). Uses bsdtar or unzip for the optional
# METADATA cross-check; skips it gracefully if neither is present.

set -uo pipefail

PROG=${0##*/}

# Print the header comment block (everything after the shebang, up to the first
# non-comment line) as the help text, so the two can never drift apart.
usage() { awk 'NR>2 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"; }

die() { printf '%s: error: %s\n' "$PROG" "$*" >&2; exit 1; }

# ---------------------------------------------------------------- options ----
OUTDIR=""
ABS=1
ALLOW_MISMATCH=0
META_CHECK=1
DRY_RUN=0

while [ $# -gt 0 ]; do
    case $1 in
        -o|--outdir)          [ $# -ge 2 ] || die "$1 needs an argument"; OUTDIR=$2; shift 2 ;;
        --rel)                ABS=0; shift ;;
        --abs)                ABS=1; shift ;;   # accepted for compatibility; now the default
        --allow-mismatch)     ALLOW_MISMATCH=1; shift ;;
        --no-metadata-check)  META_CHECK=0; shift ;;
        -n|--dry-run)         DRY_RUN=1; shift ;;
        -h|--help)            usage; exit 0 ;;
        --)                   shift; break ;;
        -*)                   die "unknown option: $1" ;;
        *)                    break ;;
    esac
done

[ $# -eq 2 ] || { usage >&2; exit 1; }

WHEEL_DIR=${1%/}
LIST_FILE=$2

[ -d "$WHEEL_DIR" ]  || die "wheel directory not found: $WHEEL_DIR"
[ -f "$LIST_FILE" ]  || die "list file not found: $LIST_FILE"

# Locate an archive reader for the METADATA cross-check.
READER=""
if [ "$META_CHECK" -eq 1 ]; then
    if command -v bsdtar >/dev/null 2>&1; then READER=bsdtar
    elif command -v unzip >/dev/null 2>&1; then READER=unzip
    fi
fi

# ---------------------------------------------------------------- helpers ----

# PEP 503 normalization. Sets _norm. Avoids forking when the name is already clean.
_norm=""
normalize() {
    case $1 in
        *[A-Z_.]*|*--*)
            _norm=$(printf '%s\n' "$1" | awk '{s=tolower($0); gsub(/[-_.]+/,"-",s); print s}') ;;
        *)
            _norm=$1 ;;
    esac
}

# Strip leading and trailing whitespace without forking. Sets _trim.
_trim=""
trim() {
    _trim=$1
    case $_trim in
        *[[:space:]]*)
            while [ "${_trim#[[:space:]]}" != "$_trim" ]; do _trim=${_trim#[[:space:]]}; done
            while [ "${_trim%[[:space:]]}" != "$_trim" ]; do _trim=${_trim%[[:space:]]}; done ;;
    esac
}

# Parse a wheel filename per PEP 427: name-version(-build)?-py-abi-plat.whl
# Name and version never contain "-" (escaped to "_"), so the first two fields are
# unambiguous. Sets _wname and _wver; returns 1 if malformed.
_wname=""; _wver=""
parse_wheel() {
    local base dashes rest
    base=${1##*/}
    base=${base%.whl}
    dashes=${base//[^-]/}
    [ ${#dashes} -ge 4 ] || return 1
    _wname=${base%%-*}
    rest=${base#*-}
    _wver=${rest%%-*}
    [ -n "$_wname" ] && [ -n "$_wver" ]
}

# Project name from dist-info METADATA. Sets _mname ("" if unavailable).
_mname=""
metadata_name() {
    _mname=""
    [ -n "$READER" ] || return 0
    case $READER in
        bsdtar)
            _mname=$(bsdtar -O -xf "$1" '*.dist-info/METADATA' 2>/dev/null \
                     | awk '/^Name:/ {sub(/^Name:[ \t]*/,""); print; exit}') ;;
        unzip)
            local member
            member=$(unzip -Z1 "$1" 2>/dev/null | awk '/\.dist-info\/METADATA$/ {print; exit}')
            [ -n "$member" ] || return 0
            _mname=$(unzip -p "$1" "$member" 2>/dev/null \
                     | awk '/^Name:/ {sub(/^Name:[ \t]*/,""); print; exit}') ;;
    esac
    return 0
}

# Every wheel path is "$WHEEL_DIR/<basename>", so resolve the directory once.
WHEEL_DIR_ABS=$(cd "$WHEEL_DIR" && pwd -P) || die "cannot resolve $WHEEL_DIR"

# ------------------------------------------------------------ scan wheels ----
# Parallel indexed arrays (bash 3.2 has no associative arrays). The data is tiny.
W_KEY=(); W_VER=(); W_PATH=(); W_HIT=()
MALFORMED=(); CONFLICTS=(); DUPES=()

nwheels=0
for whl in "$WHEEL_DIR"/*.whl; do
    [ -e "$whl" ] || continue
    nwheels=$((nwheels + 1))

    if ! parse_wheel "$whl"; then
        MALFORMED+=("${whl##*/}")
        continue
    fi

    normalize "$_wname"; key=$_norm
    ver=$_wver

    if [ "$META_CHECK" -eq 1 ]; then
        metadata_name "$whl"
        if [ -n "$_mname" ]; then
            normalize "$_mname"
            if [ "$_norm" != "$key" ]; then
                CONFLICTS+=("${whl##*/}: filename says '$key', METADATA says '$_norm'")
                key=$_norm            # METADATA is authoritative
            fi
        fi
    fi

    # Duplicate check against everything already indexed.
    i=0
    while [ $i -lt ${#W_KEY[@]} ]; do
        if [ "${W_KEY[$i]}" = "$key" ]; then
            DUPES+=("$key: ${W_PATH[$i]##*/} AND ${whl##*/}")
            break
        fi
        i=$((i + 1))
    done

    W_KEY+=("$key"); W_VER+=("$ver"); W_PATH+=("$whl"); W_HIT+=(0)
done

[ ${#W_KEY[@]} -gt 0 ] || [ ${#MALFORMED[@]} -gt 0 ] || die "no .whl files in $WHEEL_DIR"

# Find the best wheel for a key: exact version match wins, else first by name.
# Sets _idx to the array index, or -1.
_idx=-1
find_wheel() {
    local key=$1 want=$2 i=0 first=-1
    while [ $i -lt ${#W_KEY[@]} ]; do
        if [ "${W_KEY[$i]}" = "$key" ]; then
            [ $first -lt 0 ] && first=$i
            if [ "${W_VER[$i]}" = "$want" ]; then _idx=$i; return 0; fi
        fi
        i=$((i + 1))
    done
    _idx=$first
    [ $first -ge 0 ]
}

# -------------------------------------------------------- walk the list ------
NOWHEELS=(); WHEELS=(); MATCHED=(); MISMATCHED=(); PASSTHRU=()

PIN_RE='^([A-Za-z0-9][A-Za-z0-9._-]*)[[:space:]]*==[[:space:]]*([^[:space:];#]+)[[:space:]]*(.*)$'

lineno=0
total=0
while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    total=$((total + 1))
    line=${line%$'\r'}

    trim "$line"; stripped=$_trim

    # Blank lines and comments flow through untouched.
    case $stripped in
        "" |\#*)
            NOWHEELS+=("$line"); continue ;;
        -*)
            NOWHEELS+=("$line")
            PASSTHRU+=("line $lineno: pip option passed through: $stripped")
            continue ;;
    esac

    if [[ ! $stripped =~ $PIN_RE ]]; then
        NOWHEELS+=("$line")
        PASSTHRU+=("line $lineno: not a '==' pin, passed through: $stripped")
        continue
    fi

    name=${BASH_REMATCH[1]}
    listver=${BASH_REMATCH[2]}
    rest=${BASH_REMATCH[3]}

    normalize "$name"; key=$_norm

    if ! find_wheel "$key" "$listver"; then
        NOWHEELS+=("$line")
        continue
    fi

    W_HIT[$_idx]=1
    wpath=${W_PATH[$_idx]}
    [ "$ABS" -eq 1 ] && wpath="$WHEEL_DIR_ABS/${wpath##*/}"
    WHEELS+=("$wpath")

    if [ "${W_VER[$_idx]}" = "$listver" ]; then
        MATCHED+=("$key==$listver  ->  ${W_PATH[$_idx]##*/}")
    else
        MISMATCHED+=("line $lineno: $key: list pins '$listver' but wheel is '${W_VER[$_idx]}'  (${W_PATH[$_idx]##*/})")
    fi

    [ -n "$rest" ] && PASSTHRU+=("line $lineno: $key: dropped trailing text when substituting wheel: '$rest'")
done < "$LIST_FILE"

UNREFERENCED=()
i=0
while [ $i -lt ${#W_KEY[@]} ]; do
    [ "${W_HIT[$i]}" -eq 0 ] && UNREFERENCED+=("${W_PATH[$i]##*/}")
    i=$((i + 1))
done

# ----------------------------------------------------------- write output ----
base=${LIST_FILE##*/}
stem=${base%.*}
dir=${LIST_FILE%/*}
[ "$dir" = "$LIST_FILE" ] && dir=.
[ -n "$OUTDIR" ] && dir=$OUTDIR

OUT_NOWHEELS="$dir/${stem}_nowheels.list"
OUT_WHEELS="$dir/${stem}_wheels.list"
OUT_REPORT="$dir/${stem}_report.txt"

TMPREPORT=$(mktemp "${TMPDIR:-/tmp}/prepreq.XXXXXX") || die "cannot create temp file"
trap 'rm -f "$TMPREPORT"' EXIT

RULE="------------------------------------------------------------------------"

section() {
    local title=$1; shift
    printf '%s (%d)\n%s\n' "$title" "$#" "$RULE" >> "$TMPREPORT"
    if [ $# -eq 0 ]; then
        printf '  (none)\n' >> "$TMPREPORT"
    else
        printf '  %s\n' "$@" >> "$TMPREPORT"
    fi
    printf '\n' >> "$TMPREPORT"
}

{
    printf 'Requirements split report\n========================================================================\n'
    printf 'list file   : %s\n' "$LIST_FILE"
    printf 'wheel dir   : %s\n' "$WHEEL_DIR"
    printf 'generated   : %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf 'list entries        : %d\n' "$total"
    printf '  -> no-wheel list  : %d\n' "${#NOWHEELS[@]}"
    printf '  -> wheel list     : %d\n' "${#WHEELS[@]}"
    printf 'wheels in directory : %d\n\n' "$nwheels"
} > "$TMPREPORT"

section "MATCHED (name and version agree)"                    ${MATCHED[@]+"${MATCHED[@]}"}
section "VERSION MISMATCH -- wheel substituted anyway"         ${MISMATCHED[@]+"${MISMATCHED[@]}"}
section "DUPLICATE WHEELS -- ambiguous, resolve before install" ${DUPES[@]+"${DUPES[@]}"}
section "WHEELS NOT REFERENCED BY THE LIST"                    ${UNREFERENCED[@]+"${UNREFERENCED[@]}"}
section "MALFORMED WHEEL FILENAMES"                            ${MALFORMED[@]+"${MALFORMED[@]}"}
section "FILENAME / METADATA NAME CONFLICTS"                   ${CONFLICTS[@]+"${CONFLICTS[@]}"}
section "PASSED THROUGH VERBATIM"                              ${PASSTHRU[@]+"${PASSTHRU[@]}"}

if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$dir" || die "cannot create output directory: $dir"
    : > "$OUT_NOWHEELS"
    [ ${#NOWHEELS[@]} -gt 0 ] && printf '%s\n' "${NOWHEELS[@]}" > "$OUT_NOWHEELS"
    : > "$OUT_WHEELS"
    [ ${#WHEELS[@]} -gt 0 ] && printf '%s\n' "${WHEELS[@]}" > "$OUT_WHEELS"
    cp "$TMPREPORT" "$OUT_REPORT"
fi

# --------------------------------------------------------------- summary ----
printf '%d no-wheel + %d wheel = %d lines (input: %d)\n' \
    "${#NOWHEELS[@]}" "${#WHEELS[@]}" "$((${#NOWHEELS[@]} + ${#WHEELS[@]}))" "$total"

[ ${#MISMATCHED[@]}  -gt 0 ] && printf '  !! %d version mismatch\n'            "${#MISMATCHED[@]}"
[ ${#DUPES[@]}       -gt 0 ] && printf '  !! %d duplicate wheels\n'            "${#DUPES[@]}"
[ ${#MALFORMED[@]}   -gt 0 ] && printf '  !! %d malformed wheel filenames\n'   "${#MALFORMED[@]}"
[ ${#CONFLICTS[@]}   -gt 0 ] && printf '  !! %d filename/METADATA conflicts\n' "${#CONFLICTS[@]}"
[ ${#UNREFERENCED[@]} -gt 0 ] && printf '  -- %d wheels not referenced by the list\n' "${#UNREFERENCED[@]}"
[ -z "$READER" ] && [ "$META_CHECK" -eq 1 ] && printf '  -- no bsdtar/unzip: METADATA cross-check skipped\n'

if [ "$DRY_RUN" -eq 1 ]; then
    printf '\ndry run -- report follows, no files written\n\n'
    cat "$TMPREPORT"
else
    printf 'wrote %s\n' "$OUT_NOWHEELS"
    printf 'wrote %s\n' "$OUT_WHEELS"
    printf 'wrote %s\n' "$OUT_REPORT"
fi

problems=0
[ ${#DUPES[@]}     -gt 0 ] && problems=1
[ ${#MALFORMED[@]} -gt 0 ] && problems=1
[ ${#CONFLICTS[@]} -gt 0 ] && problems=1
[ ${#MISMATCHED[@]} -gt 0 ] && [ "$ALLOW_MISMATCH" -eq 0 ] && problems=1

if [ "$problems" -eq 1 ]; then
    printf '%s: exit 2 -- see the report before installing\n' "$PROG" >&2
    exit 2
fi
exit 0
