#!/usr/bin/env bash
#
# collect_rpath_data.sh -- read-only RPATH/RUNPATH/DT_NEEDED survey of a conda prefix.
#
# Usage:
#   ./collect_rpath_data.sh [options] <env_prefix> <outdir>
#
# Makes ONE slow pass over the tree and writes machine-readable files, so every
# later question is an instant grep instead of another walk over Lustre.
#
# Outputs in <outdir>:
#   elf_files.txt    every *.so* regular file under the prefix (what we readelf/ldd)
#   provides.txt     the same, plus symlinks -- every *name* the prefix can satisfy
#   dynamic.tsv      path <TAB> NEEDED|RUNPATH|RPATH|SONAME <TAB> value
#   resolution.tsv   path <TAB> needed <TAB> resolved-path|NOTFOUND
#   ldd_raw.txt      raw ldd output, LD_LIBRARY_PATH unset
#   leaks.tsv        THE WORK LIST: consumer <TAB> soname <TAB> foreign path <TAB>
#                    the same soname inside this prefix (what it should have picked)
#   summary.txt      small enough to paste into a conversation
#
# Options:
#   --skip-ldd     dynamic section only (fast); no resolution data
#   --force        recollect even if outputs already exist
#   -h, --help     this message
#
# Nothing is modified. No patchelf. Safe to run on a read-only deployed image.
#
# THE DEFECT THIS FINDS: a library in this prefix whose DT_NEEDED resolves into a
# DIFFERENT conda env -- typically the build env the wheel was compiled in. The
# correct copy is present here; the loader just prefers the baked-in absolute path.
# Nothing errors, so it is invisible until that other env is unreachable. Section 6
# and leaks.tsv list every instance.
#
# "Foreign" means absolute, outside this prefix, and not a system location. It is
# deliberately NOT "starts with /lus": these prefixes live on /lus themselves, so
# that test would flag every correct entry and miss a build prefix on /home.
#
# Resolution is measured with LD_LIBRARY_PATH UNSET, which is the acceptance
# criterion: what resolves on RPATH/RUNPATH alone. oneAPI and MPI libraries are
# EXPECTED to show NOTFOUND under that condition -- they are system/module-provided
# (category 3) and out of scope. The summary separates them from real problems.

set -uo pipefail

PROG=${0##*/}
# Bump on any change to classification or collection. It is printed into
# summary.txt so a pasted report always says which build produced it, and
# run_collection.sh refuses to run against an older one.
COLLECTOR_VERSION=2026-09-01
usage() { awk 'NR>2 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"; }
die() { printf '%s: error: %s\n' "$PROG" "$*" >&2; exit 1; }
# BSD wc pads its output ("       7"); strip it so arithmetic and %d work.
count() { wc -l < "$1" | tr -d '[:space:]'; }

# Libraries owned by the system: module-provided oneAPI, MPI, HDF5 and GPU runtime,
# libc and friends, plus the CUDA/ROCm sonames a portable torch build references but
# that no Intel-GPU node has. NOTFOUND for one of these is expected, not a defect.
# libpython3 is here for a different reason: the running interpreter has already
# provided it, so ldd's verdict on an extension module is meaningless.
SYSTEM_RE='^(libsycl|libur_|libumf|libmkl|libtbb|libccl|libintlc|libimf|libsvml|libirng|libiomp|libpti|libze_|libOpenCL|libtcm|libhwloc|libonemkl|libnuma|libfabric|libmpi|libmpich|libpmi|libcxi|libjson-c|libcuda|libnvidia|libhdf5|libpython3|libcublas|libcudart|libcudnn|libcufft|libcurand|libcusparse|libcusolver|libnccl|libnvrtc|libhip|librocm|librocrand|libamdhip|libav|libsw|libnsl|libcrypt|libquadmath)'

# A path counts as FOREIGN when it is absolute, lives outside the prefix being
# surveyed, and is not a system location. Testing for /lus instead would be wrong
# twice over: the surveyed prefix is itself on /lus (so every correct entry would
# be flagged), and a build prefix on /home or /soft would be missed.
SYSPATH_RE='^(/usr|/lib|/lib64|/opt|/etc|/bin|/sbin|/proc|/sys|/var)/'

SKIP_LDD=0
FORCE=0
while [ $# -gt 0 ]; do
    case $1 in
        --skip-ldd) SKIP_LDD=1; shift ;;
        --force)    FORCE=1; shift ;;
        -h|--help)  usage; exit 0 ;;
        --)         shift; break ;;
        -*)         die "unknown option: $1" ;;
        *)          break ;;
    esac
done

[ $# -eq 2 ] || { usage >&2; exit 1; }
PREFIX=${1%/}
OUTDIR=${2%/}

[ -d "$PREFIX" ] || die "prefix not found: $PREFIX"
command -v readelf >/dev/null 2>&1 || die "readelf not on PATH (need binutils)"
mkdir -p "$OUTDIR" || die "cannot create $OUTDIR"

PREFIX_ABS=$(cd "$PREFIX" && pwd -P)
SITE=$(ls -d "$PREFIX_ABS"/lib/python*/site-packages 2>/dev/null | head -1)
[ -n "$SITE" ] || die "no lib/python*/site-packages under $PREFIX_ABS"

printf '%s: surveying %s\n' "$PROG" "$PREFIX_ABS" >&2
printf '  site-packages: %s\n' "$SITE" >&2

# ------------------------------------------------------------------ find ELFs --
# Two lists, deliberately. elf_files.txt is regular files only -- readelf and ldd
# must not see the same object once per symlink pointing at it. provides.txt adds
# the symlinks, because a DT_NEEDED soname is usually a link onto the real file
# (libglog.so.0 -> libglog.so.0.4.0), so a name lookup against regular files alone
# reports every versioned conda library as absent from the prefix.
if [ "$FORCE" -eq 1 ] || [ ! -s "$OUTDIR/elf_files.txt" ] || [ ! -s "$OUTDIR/provides.txt" ]; then
    printf '  [1/3] finding shared objects ... ' >&2
    find "$SITE" "$PREFIX_ABS/lib" -maxdepth 12 -type f -name '*.so*' 2>/dev/null \
        | sort -u > "$OUTDIR/elf_files.txt"
    find "$SITE" "$PREFIX_ABS/lib" -maxdepth 12 \( -type f -o -type l \) -name '*.so*' 2>/dev/null \
        | sort -u > "$OUTDIR/provides.txt"
    printf '%d found, %d names\n' \
        "$(count "$OUTDIR/elf_files.txt")" "$(count "$OUTDIR/provides.txt")" >&2
else
    printf '  [1/3] reusing elf_files.txt (%d), provides.txt (%d)\n' \
        "$(count "$OUTDIR/elf_files.txt")" "$(count "$OUTDIR/provides.txt")" >&2
fi

NELF=$(count "$OUTDIR/elf_files.txt")
[ "$NELF" -gt 0 ] || die "no shared objects found -- is the env installed?"

# ------------------------------------------------------- dynamic section pass --
# One readelf per file with our own marker line. readelf only prints its "File:"
# header when given several files at once, so emitting the marker ourselves keeps
# the parse correct no matter how the batch falls.
if [ "$FORCE" -eq 1 ] || [ ! -s "$OUTDIR/dynamic.tsv" ]; then
    printf '  [2/3] reading dynamic sections (%d files, a few minutes on Lustre) ... ' "$NELF" >&2
    while IFS= read -r f; do
        printf '===FILE\t%s\n' "$f"
        readelf -d "$f" 2>/dev/null
    done < "$OUTDIR/elf_files.txt" \
    | awk -F'\t' '
        function val(s,   i,j) { i=index(s,"["); j=index(s,"]");
                                 return (i && j > i) ? substr(s, i+1, j-i-1) : "" }
        /^===FILE\t/ { f=$2; next }
        /\(NEEDED\)/  { print f "\tNEEDED\t"  val($0); next }
        /\(RUNPATH\)/ { print f "\tRUNPATH\t" val($0); next }
        /\(RPATH\)/   { print f "\tRPATH\t"   val($0); next }
        /\(SONAME\)/  { print f "\tSONAME\t"  val($0); next }
      ' > "$OUTDIR/dynamic.tsv"
    printf '%d records\n' "$(count "$OUTDIR/dynamic.tsv")" >&2
else
    printf '  [2/3] reusing dynamic.tsv\n' >&2
fi

# ------------------------------------------------------------- resolution pass --
if [ "$SKIP_LDD" -eq 1 ]; then
    printf '  [3/3] skipped (--skip-ldd)\n' >&2
    : > "$OUTDIR/resolution.tsv"
elif [ "$FORCE" -eq 1 ] || [ ! -s "$OUTDIR/resolution.tsv" ]; then
    printf '  [3/3] resolving with LD_LIBRARY_PATH unset (slower) ... ' >&2
    while IFS= read -r f; do
        printf '===FILE\t%s\n' "$f"
        env -u LD_LIBRARY_PATH ldd "$f" 2>/dev/null
    done < "$OUTDIR/elf_files.txt" > "$OUTDIR/ldd_raw.txt"
    awk -F'\t' '
        /^===FILE\t/ { f=$2; next }
        /=>/ {
            line=$0
            sub(/^[ \t]+/, "", line)
            n=index(line, " => ")
            if (!n) next
            lib=substr(line, 1, n-1)
            tgt=substr(line, n+4)
            sub(/ \(0x[0-9a-f]*\)$/, "", tgt)
            if (tgt ~ /not found/) tgt="NOTFOUND"
            print f "\t" lib "\t" tgt
        }
      ' "$OUTDIR/ldd_raw.txt" > "$OUTDIR/resolution.tsv"
    printf '%d edges\n' "$(count "$OUTDIR/resolution.tsv")" >&2
else
    printf '  [3/3] reusing resolution.tsv\n' >&2
fi

# ----------------------------------------------------------------- leak table --
# The work list: every dependency that resolves into some OTHER conda env.
# consumer <TAB> soname <TAB> foreign path <TAB> same soname inside this prefix, if any
if [ -s "$OUTDIR/resolution.tsv" ]; then
    awk -F'\t' -v pfx="$PREFIX_ABS" -v syspath="$SYSPATH_RE" '
        FNR==NR {                                   # pass 1: every name we provide
            p=$0; n=split(p, a, "/"); base=a[n]     # symlinks included -- see above
            if (!(base in have)) have[base]=p
            next
        }
        $3 != "NOTFOUND" && $3 ~ /^\// && index($3, pfx) != 1 && $3 !~ syspath {
            print $1 "\t" $2 "\t" $3 "\t" ($2 in have ? have[$2] : "-- not in this prefix --")
        }' "$OUTDIR/provides.txt" "$OUTDIR/resolution.tsv" > "$OUTDIR/leaks.tsv"
else
    : > "$OUTDIR/leaks.tsv"
fi

# -------------------------------------------------------------------- summary --
printf '  writing summary ... ' >&2

SUM="$OUTDIR/summary.txt"
RULE="------------------------------------------------------------------------"

{
printf 'RPATH survey\n%s\n' "$RULE"
printf 'collector : %s\n' "$COLLECTOR_VERSION"
printf 'prefix    : %s\n' "$PREFIX_ABS"
printf 'host      : %s\n' "$(hostname 2>/dev/null)"
printf 'collected : %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
printf 'ELF files : %s\n\n' "$NELF"

printf '1. WHICH TAG\n%s\n' "$RULE"
awk -F'\t' -v tot="$NELF" '
    $2=="RUNPATH" { r[$1]=1 }
    $2=="RPATH"   { p[$1]=1 }
    END {
        nr=0; for (k in r) nr++
        np=0; for (k in p) np++
        nb=0; for (k in p) if (k in r) nb++
        printf "  RUNPATH only : %d\n", nr-nb
        printf "  RPATH only   : %d\n", np-nb
        printf "  both         : %d\n", nb
        printf "  neither      : %d\n", tot-(nr+np-nb)
    }' "$OUTDIR/dynamic.tsv"

printf '\n2. RPATH/RUNPATH ENTRIES BY CLASS\n%s\n' "$RULE"
awk -F'\t' -v pfx="$PREFIX_ABS" -v syspath="$SYSPATH_RE" '
    $2=="RUNPATH" || $2=="RPATH" {
        n=split($3, parts, ":")
        for (i=1; i<=n; i++) {
            e=parts[i]
            if (e=="") continue
            if (e ~ /^\$ORIGIN/)                     c="$ORIGIN-relative (cat 1)"
            else if (index(e, pfx)==1)               c="absolute, inside prefix (cat 2)"
            else if (e ~ syspath)                    c="system: /opt, /usr, /lib64 (cat 3/4)"
            else if (e ~ /^\//)                      c="FOREIGN prefix (DEFECT)"
            else                                     c="other"
            cnt[c]++
        }
    }
    END {
        for (k in cnt) printf "  %-40s %6d\n", k, cnt[k]
    }' "$OUTDIR/dynamic.tsv" | sort -k2 -rn

printf '\n3. DISTINCT FOREIGN BUILD PREFIXES DISCOVERED\n%s\n' "$RULE"
# "Foreign" = under /lus but NOT under the prefix we are surveying. The prefix
# itself lives on /lus, so a bare /lus/ test would flag every correct entry.
awk -F'\t' -v pfx="$PREFIX_ABS" -v syspath="$SYSPATH_RE" '
    $2=="RUNPATH" || $2=="RPATH" {
        n=split($3, parts, ":")
        for (i=1; i<=n; i++) {
            e=parts[i]
            if (e !~ /^\//)       continue          # $ORIGIN-relative or empty
            if (index(e, pfx)==1) continue          # our own prefix: not foreign
            if (e ~ syspath)      continue          # system location: out of scope
            # collapse to the conda env root: .../conda_envs/<env>
            if (match(e, /^.*\/conda_envs\/[^\/]+/)) e=substr(e, 1, RLENGTH)
            c[e]++
        }
    }
    END {
        n=0
        for (k in c) { printf "  %6d  %s\n", c[k], k; n++ }
        if (n==0) printf "  (none)\n"
    }' "$OUTDIR/dynamic.tsv" | sort -rn

if [ -s "$OUTDIR/resolution.tsv" ]; then
printf '\n4. WHERE DT_NEEDED RESOLVES (LD_LIBRARY_PATH unset)\n%s\n' "$RULE"
awk -F'\t' -v pfx="$PREFIX_ABS" -v sysre="$SYSTEM_RE" -v syspath="$SYSPATH_RE" '
    {
        if ($3=="NOTFOUND")            c = ($2 ~ sysre) ? "NOTFOUND - system-owned (expected)" \
                                                        : "NOTFOUND - OURS (defect)"
        else if (index($3, pfx)==1)    c="inside this prefix (good)"
        else if ($3 ~ syspath)         c="system path"
        else if ($3 ~ /^\//)           c="FOREIGN prefix (defect)"
        else                           c="other"
        cnt[c]++
    }
    END { for (k in cnt) printf "  %-42s %6d\n", k, cnt[k] }' "$OUTDIR/resolution.tsv" | sort -k2 -rn

printf '\n5. DEFECTS -- non-system libraries that do NOT resolve\n%s\n' "$RULE"
awk -F'\t' -v sysre="$SYSTEM_RE" '
    $3=="NOTFOUND" && $2 !~ sysre { c[$2]++ }
    END {
        n=0
        for (k in c) { printf "  %6d dependents need  %s\n", c[k], k; n++ }
        if (n==0) printf "  (none -- every non-system dependency resolves)\n"
    }' "$OUTDIR/resolution.tsv" | sort -rn

printf '\n6. CROSS-ENV LEAKS -- resolving into a DIFFERENT conda env\n%s\n' "$RULE"
printf '  These are the defects. The library exists in this prefix, but the loader\n'
printf '  picks up a copy from the build env instead. Full list in leaks.tsv.\n\n'
awk -F'\t' -v pfx="$PREFIX_ABS" -v site="$SITE" -v syspath="$SYSPATH_RE" '
    $3 != "NOTFOUND" && $3 ~ /^\// && index($3, pfx) != 1 && $3 !~ syspath {
        p=$1
        if (index(p, site)==1) { sub(site "/", "", p); split(p, a, "/"); pk=a[1] }
        else pk="(prefix)/lib"
        # Name the foreign env by its conda_envs/<name> component when there is
        # one; otherwise keep the whole path -- basenaming it would print the
        # library filename and read as if that were an env name.
        env=$3
        if (match(env, /\/conda_envs\/[^\/]+/))
            env=substr(env, RSTART+12, RLENGTH-12)   # "/conda_envs/" is 12 chars
        c[pk "\t" env]++
    }
    END {
        n=0
        for (k in c) { split(k, a, "\t"); printf "  %6d edges  %-22s -> %s\n", c[k], a[1], a[2]; n++ }
        if (n==0) printf "  (none -- nothing resolves outside this prefix)\n"
    }' "$OUTDIR/resolution.tsv" | sort -rn
fi

printf '\n7. PER-PACKAGE BREAKDOWN\n%s\n' "$RULE"
printf '  %-28s %6s %8s %11s\n' "package" "ELFs" "stale" "unresolved"
printf '  %-28s %6s %8s %11s\n' \
       "" "total" "w/ /lus" "non-system"
{
    # ELFs per package
    awk -F'\t' -v site="$SITE" '
        { p=$1; if (index(p, site)==1) { sub(site "/", "", p); split(p, a, "/"); print a[1] }
          else print "(prefix)/lib" }' "$OUTDIR/elf_files.txt" | sort | uniq -c \
        | awk '{ print "ELF\t" $2 "\t" $1 }'

    # ELFs carrying at least one stale entry -- dedupe on the FILE, then count per
    # package (deduping on the package name would cap this column at 1).
    awk -F'\t' -v site="$SITE" -v pfx="$PREFIX_ABS" -v syspath="$SYSPATH_RE" '
        $2=="RUNPATH" || $2=="RPATH" {
            n=split($3, parts, ":")
            foreign=0
            for (i=1; i<=n; i++)
                if (parts[i] ~ /^\// && index(parts[i], pfx) != 1 && parts[i] !~ syspath) foreign=1
            if (!foreign) next
            p=$1; if (index(p, site)==1) { sub(site "/", "", p); split(p, a, "/"); pk=a[1] }
            else pk="(prefix)/lib"
            print $1 "\t" pk }' "$OUTDIR/dynamic.tsv" | sort -u \
        | awk -F'\t' '{ c[$2]++ } END { for (k in c) print "STALE\t" k "\t" c[k] }'

    # non-system dependencies that do not resolve, per package
    if [ -s "$OUTDIR/resolution.tsv" ]; then
        awk -F'\t' -v site="$SITE" -v sysre="$SYSTEM_RE" '
            $3=="NOTFOUND" && $2 !~ sysre {
                p=$1; if (index(p, site)==1) { sub(site "/", "", p); split(p, a, "/"); pk=a[1] }
                else pk="(prefix)/lib"
                c[pk]++ }
            END { for (k in c) print "NOFIX\t" k "\t" c[k] }' "$OUTDIR/resolution.tsv"
    fi
} | awk -F'\t' '
    $1=="ELF"   { elf[$2]=$3 }
    $1=="STALE" { stale[$2]=$3 }
    $1=="NOFIX" { nofix[$2]=$3 }
    END { for (k in elf) printf "  %-28s %6d %8d %11d\n", k, elf[k],
                 (k in stale ? stale[k] : 0), (k in nofix ? nofix[k] : 0) }
  ' | sort -k2 -rn | head -40

printf '\n%s\nFull data: dynamic.tsv, resolution.tsv, ldd_raw.txt in %s\n' "$RULE" "$OUTDIR"
} > "$SUM" 2>&1

printf 'done\n' >&2
printf '\n' >&2
cat "$SUM"
