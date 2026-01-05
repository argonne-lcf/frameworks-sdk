#!/bin/sh

# 1) Pull source
# TODO Build in a tmpdir
git clone https://github.com/pytorch/pytorch
git submodule sync && git submodule update --init --recursive

# 2) Set PyTorch build configuration
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

# 3) Build
uv build --wheel pytorch

# 4) Verify
# TODO separate build from tests/validation
# python - <<'EOF'
# import torch, intel_extension_for_pytorch as ipex, oneccl_bindings_for_pytorch as oneccl
# print(torch.__file__)
# print(torch.__config__.show())
# print(f"torch: {torch.__version__}, XPU: {torch.xpu.is_available()} ({torch.xpu.device_count()})")
# import torch.distributed
# print(f"XCCL: {torch.distributed.is_xccl_available()}")
# print(f"IPEX: {ipex.__version__}, oneCCL: {oneccl.__version__}")
# EOF
