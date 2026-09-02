#!/usr/bin/env bash
# run_collection.sh -- read-only RPATH survey of RP1_RC4. Modifies nothing.
#
# Usage: ./run_collection.sh [--force|--reuse]
#   --force   (default) full recollection: readelf + ldd over the whole tree
#   --reuse   re-summarise cached dynamic.tsv/resolution.tsv -- seconds, no Lustre walk
set -eo pipefail

# ------------------------------------------------------------------ modules --
if ! command -v module >/dev/null 2>&1; then
  for f in /etc/profile.d/z00_lmod.sh /etc/profile.d/lmod.sh; do
      if [ -r "$f" ]; then . "$f"; break; fi
  done
fi
command -v module >/dev/null 2>&1 || { echo "lmod unavailable" >&2; exit 1; }

module add miniforge3/25.11.0-1
ml add intel_gpu_umd_aicoe/2026.06.19
module add cmake
unset CMAKE_ROOT
module add ninja
module add pti-gpu
module add hdf5

: "${MINIFORGE3_ROOT:?miniforge3 module did not load}"

set -u                              # safe now that lmod/conda sourcing is done

export ZE_FLAT_DEVICE_HIERARCHY=FLAT
export CCL_OP_SYNC=1
export CCL_ATL_SYNC_COLL=1

# ------------------------------------------------------------------- config --
TOOLS=/lus/tegu/projects/datasets/software/tools
COL=$TOOLS/collect_rpath_data.sh
# NOT named ENV: $ENV is POSIX-special and would be sourced by child sh shells.
# Overridable: each rebuild lands in a new env, and hardcoding the name here has
# already sent one survey at the previous env while the report claimed otherwise.
#   TARGET=$ENVS/RP1_RC4_torchcomms_0.3.1_rc1_python_3.12.12 OUT=... PREV= ./run_collection.sh
TARGET=${TARGET:-/lus/tegu/projects/datasets/software/26.181.0/wheelforge/envs/conda_envs/RP1_RC4_python_3.12.12}
# v2 is a fresh directory on purpose: the 2026-09-01 15:55 run stays intact as a
# comparison point, and this run is one artifact set from one collector version.
OUT=${OUT:-$TOOLS/rpath_rp1rc4_v2}
# Cross-checked against, if it exists. `-` NOT `:-` on purpose: the cross-check is
# a "did this env move underneath us" guard, so it is only meaningful for a re-run
# of the SAME prefix, and callers surveying a different env must be able to switch
# it off with `PREV=`. Under `:-` an empty value falls back to the default and the
# guard runs anyway -- diffing two unrelated envs, every row differs because
# resolution.tsv embeds the absolute prefix, and the WARNING reads as a failure.
PREV=${PREV-$TOOLS/rpath_rp1rc4}
PATCHELF=$TOOLS/bin/patchelf        # unused this pass; later phases

# This run settles the rebuild-vs-patch decision, so it recollects by default.
case ${1:-} in
    ''|--force) FORCE=--force ;;
    --reuse)    FORCE= ;;
    *)          echo "usage: ${0##*/} [--force|--reuse]" >&2; exit 1 ;;
esac

# ------------------------------------------------------------- preflight --
# Staleness gates. Each of these has produced a confidently wrong report once,
# and each failed silently -- the run completed and the numbers looked plausible.
[ -r "$COL" ] || { echo "collector not found at $COL" >&2; exit 1; }

while IFS='|' read -r pat msg; do
    grep -q "$pat" "$COL" || {
        echo "STALE collector at $COL: $msg" >&2
        echo "Re-scp tools/collect_rpath_data.sh from the Mac." >&2
        exit 1
    }
done <<'EOF'
COLLECTOR_VERSION=2026-09-01|no 2026-09-01 version stamp
provides.txt|pre-symlink-fix: versioned conda sonames (libglog.so.0) reported absent
libquadmath|pre-2026-09-01 SYSTEM_RE: ffmpeg/CUDA/hdf5 misreported as defects
EOF

n=$(grep -c SYSPATH_RE "$COL" || true)
[ "${n:-0}" -ge 6 ] || {
  echo "STALE collector at $COL: SYSPATH_RE x${n:-0}, need 6+ (pre-2026-08-31 foreign-path fix)." >&2
  echo "Re-scp tools/collect_rpath_data.sh from the Mac." >&2
  exit 1
}

# No conda activate: the survey needs no Python, and activating risks
# shadowing system readelf with a conda binutils.
for t in readelf ldd; do
  p=$(command -v "$t") || { echo "$t not on PATH" >&2; exit 1; }
  case $p in
      "$TARGET"/*) echo "REFUSING: $t resolves inside the surveyed env ($p)" >&2; exit 1 ;;
  esac
  printf '%-8s %s\n' "$t:" "$p"
done

mkdir -p "$OUT"

# ---------------------------------------------------------------- survey --
bash "$COL" ${FORCE:+"$FORCE"} "$TARGET" "$OUT" 2>&1 | tee "$OUT.log"

# ------------------------------------------------------------ sanity gate --
nres=$(wc -l < "$OUT/resolution.tsv" | tr -d '[:space:]')
echo "resolution edges: $nres"
[ "$nres" -ge 1000 ] || echo "WARNING: expected thousands — ldd may be failing silently." >&2

# ------------------------------------------- direct edges (drop transitives) --
# leaks.tsv is built from ldd, i.e. the full transitive closure. Keep only rows
# that are a real DT_NEEDED of the consumer -- that is the true work list.
awk -F'\t' 'FNR==NR { if ($2=="NEEDED") d[$1 SUBSEP $3]=1; next }
          ($1 SUBSEP $2) in d' \
  "$OUT/dynamic.tsv" "$OUT/leaks.tsv" > "$OUT/leaks_direct.tsv"

# -------------------------------------------------------------- report --
{
echo "=== collector $(sed -n 's/^COLLECTOR_VERSION=//p' "$COL" | head -1), out=$OUT"
echo "=== leaks: $(wc -l < "$OUT/leaks.tsv") total, $(wc -l < "$OUT/leaks_direct.tsv") direct"
echo
echo "=== packages with DIRECT leaks (drives rebuild-vs-patch)"
cut -f1 "$OUT/leaks_direct.tsv" | sed 's|.*/site-packages/||;s|/.*||' | sort | uniq -c | sort -rn
echo
echo "=== sonames leaking directly"
cut -f2 "$OUT/leaks_direct.tsv" | sort | uniq -c | sort -rn
echo
echo "=== no local copy -- repointing cannot fix these (expect none)"
awk -F'\t' '$4 ~ /not in this prefix/' "$OUT/leaks_direct.tsv" | cut -f2 | sort -u
echo
# Matched against provides.txt, not elf_files.txt: the latter is regular files
# only, so every versioned conda soname would look absent.
echo "=== NOTFOUND sonames that DO exist here (present, but nothing points at them)"
awk -F'\t' '$3=="NOTFOUND"{print $2}' "$OUT/resolution.tsv" | sort -u |
  while read -r s; do
      grep -q "/$s\$" "$OUT/provides.txt" && echo "  $s"
  done || true
echo
# The 2026-09-01 SYSTEM_RE added libav|libsw (ffmpeg). If torchcodec's unresolved
# count collapsed, confirm here that what vanished was ffmpeg and nothing else.
echo "=== torchcodec unresolved sonames (audit of the new libav|libsw class)"
awk -F'\t' '$1 ~ /torchcodec/ && $3=="NOTFOUND" {print $2}' "$OUT/resolution.tsv" \
  | sort -u | sed 's/^/  /'
} | tee "$OUT/decision.txt"

# ------------------------------------------ cross-check against the prior run --
# Same env, same collection logic -- SYSTEM_RE and the symlink fix are both applied
# at summary time, so resolution.tsv should be byte-identical. A difference means
# the env moved underneath us and nothing below should be trusted until it is known.
if [ -s "$PREV/resolution.tsv" ] && [ "$PREV" != "$OUT" ]; then
    echo
    if diff -q <(sort "$PREV/resolution.tsv") <(sort "$OUT/resolution.tsv") >/dev/null; then
        echo "resolution.tsv identical to $PREV — cached data was sound"
    else
        echo "WARNING: resolution.tsv DIFFERS from $PREV — the env moved. Investigate first." >&2
        diff <(sort "$PREV/resolution.tsv") <(sort "$OUT/resolution.tsv") | head -20
    fi
fi

echo
echo "Full data in $OUT — send back summary.txt and decision.txt only."
