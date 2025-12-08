#!/bin/sh

# 1) Setup a fresh Python 3.12 env in /tmp
export ENV_NAME="nightly-$(date +%Y-%m-%d)"
export BUILD_DIR="${BUILD_ROOT}/${ENV_NAME}"
mkdir -p "${BUILD_DIR}" && cd "${BUILD_DIR}"
conda create -y -q --prefix="${BUILD_DIR}" python=3.12
conda activate "${BUILD_DIR}"

#####################################################################
# Strict mode + robust traps ----------------------------------------
#####################################################################
# Fail fast, but propagate errors through functions and pipelines
set -Eeo pipefail        # -E  -->  ERR propagates out of functions

# -----------------------------------------------------------------
# Function to copy logs and wheels from compute node to Lustre ----
# -----------------------------------------------------------------
copy_out () {
      rc=$?
      echo ">>> Copying logs and wheels (exit=$rc) on $(hostname)"
      # guard in case of fail before BUILD_DIR exists
      [[ -d "${BUILD_DIR:-}" ]] || { echo "BUILD_DIR not available"; return; }

      mkdir -p "${REMOTE_ROOT}/logs" "${REMOTE_ROOT}/wheels"

      # Never let copy errors abort the trap itself
      find "$BUILD_DIR" -name '*.log' -exec cp {} "${REMOTE_ROOT}/logs/"   \; || true
      find "$BUILD_DIR" -name '*.whl' -exec cp {} "${REMOTE_ROOT}/wheels/" \; || true
}

# -----------------------------------------------------------------
# Helper to print which command died ------------------------------
# -----------------------------------------------------------------
export PROMPT_COMMAND='LAST_CMD=$BASH_COMMAND'
on_err () {
      rc=$?
      echo "✘ FAILED: \"$LAST_CMD\" (exit=$rc)"
      copy_out       # still copy logs to Lustre on error
      exit "$rc"
}

# Run copy_out on *any* exit; run on_err on real errors/signals
trap copy_out EXIT
trap on_err  ERR INT TERM
#####################################################################

# 2) Build PyTorch
git clone https://github.com/pytorch/pytorch
cd pytorch
git submodule sync && git submodule update --init --recursive
pip install cmake ninja
pip install -r requirements.txt mkl-static mkl-include
export CC="$(which gcc)" CXX="$(which g++)"
export REL_WITH_DEB_INFO=1
export USE_CUDA=0
export USE_ROCM=0
export USE_MKLDNN=1
export USE_MKL=1
export USE_FBGEMM=1
export USE_NNPACK=1
export USE_NCCL=0
export BUILD_CAFFE2_OPS=0
export BUILD_TEST=0
export USE_DISTRIBUTED=1
export USE_NUMA=0
export USE_MPI=1
export USE_XPU=1
export USE_XCCL=1
export INTEL_MKL_DIR="$MKLROOT"
export USE_AOT_DEVLIST='pvc'
export TORCH_XPU_ARCH_LIST='pvc'
#export OCLOC_VERSION=24.39.1 N.B. this doesn't match what is on the system. Let build system get correct version.
export MAX_JOBS=24
make triton > "torch-build-triton-$(date +%Y-%m-%d-%H%M%S).log" 2>&1
python setup.py bdist_wheel --verbose > "torch-build-whl-$(date +%Y-%m-%d-%H%M%S).log" 2>&1
pip install dist/*.whl
cd ../

# 6) Verify
python - <<'EOF'
import torch, intel_extension_for_pytorch as ipex, oneccl_bindings_for_pytorch as oneccl
print(torch.__file__)
print(torch.__config__.show())
print(f"torch: {torch.__version__}, XPU: {torch.xpu.is_available()} ({torch.xpu.device_count()})")
import torch.distributed
print(f"XCCL: {torch.distributed.is_xccl_available()}")
print(f"IPEX: {ipex.__version__}, oneCCL: {oneccl.__version__}")
EOF

# 7) Collect artifacts
mkdir -p artifacts
find . -type f \( -name "*.whl" -o -name "*.log" \) -exec cp --parents \{\} artifacts/ \; || true
