#!/bin/bash
# run_acceptance_torchcomms_cmake_flags.sh [--restore]
#
# Validates the proposed CMAKE_INSTALL_RPATH string by patchelf'ing the four
# INSTALLED torchcomms .so files in RP1_RC4 and re-running the survey.
# The WHEEL IS NOT TOUCHED -- this proves the string, it does not fix anything.
# Pass = leaks.tsv empty AND section 6 reads (none) AND resolution.tsv still large.
set -eo pipefail

# ------------------------------------------------------------------ modules --
module add miniforge3/25.11.0-1
ml add intel_gpu_umd_aicoe/2026.06.19
module add cmake
unset CMAKE_ROOT
module add ninja
module add pti-gpu
module add hdf5

set -u                              # safe now that lmod sourcing is done

export ZE_FLAT_DEVICE_HIERARCHY=FLAT
export CCL_OP_SYNC=1
export CCL_ATL_SYNC_COLL=1

# NO `source .../bin/activate`. Activation front-loads $CONDA_PREFIX/bin and can
# shadow the system readelf; run_collection.sh's guard only catches a readelf
# inside the surveyed env, not one from base miniforge. Nothing here needs conda.

# ------------------------------------------------------------------- config --
TOOLS=/lus/tegu/projects/datasets/software/tools
# NOT named ENV: $ENV is POSIX-special. Same reason run_collection.sh uses TARGET.
TARGET=/lus/tegu/projects/datasets/software/26.181.0/wheelforge/envs/conda_envs/RP1_RC4_python_3.12.12
TC=$TARGET/lib/python3.12/site-packages/torchcomms
BK=$TOOLS/torchcomms_backup_$(date +%Y%m%d)
PATCHELF=$TOOLS/bin/patchelf
OUT=$TOOLS/rpath_rp1rc4_patched
EXPECT_N=4

# Single-quoted, deliberately: $ORIGIN must reach the ELF literally.
RP='$ORIGIN:$ORIGIN/../torch/lib:$ORIGIN/../../..'

# ------------------------------------------------------------------ restore --
if [ "${1:-}" = "--restore" ]; then
  [ -s "$BK/SHA256SUMS" ] || { echo "no backup at $BK" >&2; exit 1; }
  cp -p "$BK"/*.so "$TC"/
  (cd "$TC" && sha256sum -c "$BK/SHA256SUMS")
  echo "restored from $BK"; exit 0
fi
[ -z "${1:-}" ] || { echo "usage: ${0##*/} [--restore]" >&2; exit 1; }

# ---------------------------------------------------------------- preflight --
[ -x "$PATCHELF" ] || { echo "patchelf not at $PATCHELF" >&2; exit 1; }
pv=$("$PATCHELF" --version | awk '{print $NF}')
case $pv in
  0.1[0-7].*|0.[0-9].*) echo "patchelf $pv: 0.17.x corrupts on section growth, need >= 0.18" >&2; exit 1 ;;
esac
printf 'patchelf %s (%s)\n' "$pv" "$PATCHELF"

rd=$(command -v readelf) || { echo "readelf not on PATH" >&2; exit 1; }
case $rd in
  "$TARGET"/*|*/miniforge*|*/conda*) echo "REFUSING: readelf from a conda tree ($rd)" >&2; exit 1 ;;
esac
printf 'readelf  %s\n' "$rd"

# Literal glob or a changed layout must fail here, not silently produce 25 leaks.
shopt -s nullglob
files=( "$TC"/*.so )
shopt -u nullglob
n=${#files[@]}
[ "$n" -eq "$EXPECT_N" ] || {
  echo "expected $EXPECT_N .so in $TC, found $n -- layout changed, re-check the \$ORIGIN offsets" >&2
  exit 1
}

# ------------------------------------------------------------------ backup --
# The four originals ARE the broken baseline. A second run must never overwrite
# them with already-patched files.
if [ -s "$BK/SHA256SUMS" ]; then
  echo "backup exists at $BK -- reusing, NOT re-copying"
else
  mkdir -p "$BK"
  cp -p "${files[@]}" "$BK/"
  ( cd "$BK" && sha256sum *.so > SHA256SUMS )
  echo "backed up $n files to $BK"
fi

# ------------------------------------------------------------------- patch --
bad=0
for f in "${files[@]}"; do
  "$PATCHELF" --set-rpath "$RP" "$f" || { echo "  patchelf FAILED: $f"; bad=1; continue; }

  # Verify per file. Never trust patchelf's exit status alone.
  if readelf -d "$f" | grep -q '(RPATH)'; then
      echo "  BAD $f: DT_RPATH present, wanted DT_RUNPATH"; bad=1
  fi
  got=$(readelf -d "$f" | awk -F'[][]' '/RUNPATH/{print $2; exit}')
  if [ "$got" != "$RP" ]; then
      echo "  BAD $f"; echo "      got:  $got"; echo "      want: $RP"; bad=1
  else
      echo "  ok  ${f##*/}"
  fi
done
[ "$bad" -eq 0 ] || { echo "patch verification failed -- not running the survey" >&2; exit 1; }

# ------------------------------------------------------------------ survey --
# PREV= disables the cross-check against the unpatched run: it is *supposed* to
# differ now, and a WARNING there would read as a failure to the next person.
OUT="$OUT" PREV= bash "$TOOLS/run_collection.sh" --force

# ------------------------------------------------------------------ verdict --
nres=$(wc -l < "$OUT/resolution.tsv" | tr -d '[:space:]')
nleak=$(wc -l < "$OUT/leaks.tsv"     | tr -d '[:space:]')
ndir=$(wc -l < "$OUT/leaks_direct.tsv" | tr -d '[:space:]')
echo
echo "resolution edges $nres | leaks $nleak total, $ndir direct"

# An empty leaks.tsv is also what a silently-broken run looks like. Check both.
if [ "$nres" -lt 1000 ]; then
  echo "INCONCLUSIVE: only $nres resolution edges -- ldd was failing. Not a pass." >&2
  exit 2
elif [ "$nleak" -eq 0 ] && [ "$ndir" -eq 0 ]; then
  echo "PASS -- the CMAKE_INSTALL_RPATH string is correct. Put it in the diff and rebuild."
else
  echo "FAIL -- $ndir direct leaks remain:" >&2
  cut -f1,2 "$OUT/leaks_direct.tsv" | sort -u | sed 's/^/  /' >&2
  exit 1
fi

