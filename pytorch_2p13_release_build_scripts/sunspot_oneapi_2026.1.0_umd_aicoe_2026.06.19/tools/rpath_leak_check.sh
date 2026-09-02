#!/bin/bash
ENV=/lus/tegu/projects/datasets/software/26.181.0/wheelforge/envs/conda_envs/RP1_RC4_python_3.12.12
FOREIGN=/lus/tegu/projects/datasets/software/26.181.0/wheelforge/envs/conda_envs/triton_3.7.1_torchcomms_0.3.1-rc1_vllm_0.25.1_nre_pt_2.13.0_rel_one_2026.1.0_np_2.3.5_python_3.12.12
#
module add miniforge3/25.11.0-1
ml add intel_gpu_umd_aicoe/2026.06.19
module add cmake
unset CMAKE_ROOT
module add ninja
module add pti-gpu
module add hdf5

: "${MINIFORGE3_ROOT:?miniforge3 module did not load}"
source "$MINIFORGE3_ROOT/bin/activate"

export ZE_FLAT_DEVICE_HIERARCHY=FLAT
export CCL_OP_SYNC=1
export CCL_ATL_SYNC_COLL=1
#
for f in lib/libglog.so.0 lib/libgflags.so.2.2 \
       lib/python3.12/site-packages/torch/lib/libc10_xpu.so; do
  echo "=== $f"
  for d in "$ENV" "$FOREIGN"; do
      if [ -e "$d/$f" ]; then stat -Lc '%10s  %n' "$d/$f"
      else                    echo "   MISSING  $d/$f"; fi
  done
  cmp "$ENV/$f" "$FOREIGN/$f"          # no -s: let it say why
done
## Clarification on what's the diffrenece in libc10_xpu.so
for d in "$ENV" "$FOREIGN"; do
    f=$d/lib/python3.12/site-packages/torch/lib/libc10_xpu.so
    echo "=== ${d##*/}"
    readelf -n "$f" | grep -A1 -i 'build id'
    readelf -d "$f" | grep -E 'RUNPATH|RPATH|SONAME'
done
ls -d $ENV/lib/python3.12/site-packages/torch-*.dist-info \
    $FOREIGN/lib/python3.12/site-packages/torch-*.dist-info
#
## If there are any ABI mismatch
ldd -r $ENV/lib/python3.12/site-packages/torchcomms/libtorchcomms.so 2>&1 \
    | grep -i 'undefined symbol' | head -20
