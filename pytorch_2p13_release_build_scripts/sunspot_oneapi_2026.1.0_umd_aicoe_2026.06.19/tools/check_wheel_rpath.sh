#!/usr/bin/env bash
# check_wheel_rpath.sh -- read-only RPATH audit of a wheel, before it is installed.
#
# Usage: ./check_wheel_rpath.sh [-q] <wheel> [<wheel> ...]
#   -q   quiet: print only findings and the verdict
#
# Unpacks each wheel into a temp dir and reports the RPATH/RUNPATH of every .so
# in it. Nothing is installed, no env is touched, the wheel is not modified.
#
# This is the cheapest gate in the chain: it catches "the CMake diff did not
# apply" or "CMake ignored the setting" in seconds, before an install, an env
# build, or a Lustre-wide survey. It is also the only check that looks at the
# actual deliverable -- collect_rpath_data.sh surveys an *installed env*, which
# is one pip operation removed from the artifact we ship.
#
# Exit: 0 clean, 1 usage/fatal, 2 findings.
set -eo pipefail

PROG=${0##*/}
CHECKER_VERSION=2026-09-01

# System locations: an absolute entry pointing here is out of scope by policy
# (categories 3 and 4 -- module-provided oneAPI and libc). Reported, not failed.
SYSTEM_RE='^/(usr|lib|lib64|opt|etc|bin|sbin|proc|sys|var)(/|$)'

QUIET=0
case ${1:-} in
    -q) QUIET=1; shift ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
[ $# -ge 1 ] || { echo "usage: $PROG [-q] <wheel> [<wheel> ...]" >&2; exit 1; }

command -v unzip   >/dev/null || { echo "unzip not found"   >&2; exit 1; }
command -v readelf >/dev/null || { echo "readelf not found" >&2; exit 1; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/wheelrpath.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM

say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }

findings=0
nso=0

for whl in "$@"; do
    [ -r "$whl" ] || { echo "cannot read $whl" >&2; exit 1; }
    d=$TMP/$(basename "$whl" .whl)
    mkdir -p "$d"
    unzip -q -o "$whl" -d "$d"

    say "=== ${whl##*/}"

    # -type f only: wheels do not normally contain symlinks, and if one appears
    # we want to readelf the real file once, not once per name.
    find "$d" -type f -name '*.so*' 2>/dev/null | sort | while IFS= read -r f; do
        rel=${f#"$d"/}
        printf 'x' >> "$TMP/.nso"

        # `|| true` is load-bearing: under `set -o pipefail` a grep that matches
        # nothing (an ELF with no RPATH at all -- the common case) fails the
        # whole pipeline, and the assignment would then kill the script.
        tag=$(readelf -d "$f" 2>/dev/null | grep -Eo '\((RPATH|RUNPATH)\)' | head -1 | tr -d '()' || true)
        val=$(readelf -d "$f" 2>/dev/null | awk -F'[][]' '/RPATH|RUNPATH/{print $2; exit}' || true)

        if [ -z "$tag" ]; then
            # Not a defect. Torch extensions routinely carry no RPATH at all and
            # rely on `import torch` having dlopen'd libtorch RTLD_GLOBAL first.
            say "  --   $rel (no RPATH/RUNPATH -- torch-extension idiom)"
            continue
        fi

        # DT_RPATH is not what we want: it is not overridable by LD_LIBRARY_PATH,
        # so a module-provided oneAPI could no longer win. Report, do not fail.
        [ "$tag" = "RPATH" ] && say "  note $rel uses DT_RPATH, not DT_RUNPATH"

        bad=""
        oldIFS=$IFS; IFS=:
        for e in $val; do
            case $e in
                '$ORIGIN'*|'${ORIGIN}'*) ;;                       # relocatable -- fine
                /*) if printf '%s' "$e" | grep -qE "$SYSTEM_RE"
                    then say "  note $rel system entry: $e"
                    else bad="$bad$e "
                    fi ;;
                '') ;;                                            # empty field
                *)  bad="$bad$e "                                 # relative, non-$ORIGIN
                    ;;
            esac
        done
        IFS=$oldIFS

        if [ -n "$bad" ]; then
            printf '  FAIL %s\n' "$rel"
            printf '       %s\n' "$tag: $val"
            for e in $bad; do printf '       non-relocatable: %s\n' "$e"; done
            printf 'x' >> "$TMP/.findings"
        else
            say "  ok   $rel"
            say "       $tag: $val"
        fi
    done
done

# The while loop above runs in a subshell (pipe from find), so counters come
# back through files rather than variables.
[ -f "$TMP/.nso" ]      && nso=$(wc -c < "$TMP/.nso"      | tr -d '[:space:]')
[ -f "$TMP/.findings" ] && findings=$(wc -c < "$TMP/.findings" | tr -d '[:space:]')

echo
echo "checker $CHECKER_VERSION | $# wheel(s), $nso shared objects, $findings finding(s)"
if [ "${findings:-0}" -gt 0 ]; then
    echo "FAIL -- a non-relocatable RPATH entry ships in the wheel."
    exit 2
fi
echo "PASS -- every RPATH entry is \$ORIGIN-relative or a system location."
