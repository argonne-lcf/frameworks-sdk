#!/bin/bash -x
#
# Time Stamp
tstamp() {
     date +"%Y-%m-%d-%H%M%S"
}
## Proxies to clone from a compute node
export HTTP_PROXY=http://proxy.alcf.anl.gov:3128
export HTTPS_PROXY=http://proxy.alcf.anl.gov:3128
export http_proxy=http://proxy.alcf.anl.gov:3128
#
CONDA_ENV_INSTALL_DIR=/lus/flare/projects/datasets/softwares/envs/conda_envs
CONDA_ENV_NAME=triton_xpu_3.5.0+git1b0418a9_no_patch_pytorch_2.9.1a0+gitd29deef_numpy_2.3.4_oneapi_2025.2.0_python_3.12.8

WHEELHOUSE_TMP=/lus/flare/projects/datasets/softwares/envs/wheelhouse_tmp/vllm_gpt_oss
PYTORCH_REPO_DIR=/lus/flare/projects/datasets/softwares/envs/repositories/pytorch_2.9.0_11_05_2025/pytorch

source /opt/aurora/25.190.0/spack/unified/0.10.1/install/linux-sles15-x86_64/gcc-13.3.0/miniforge3-24.3.0-0-gfganax/bin/activate

ENVPREFIX=$CONDA_ENV_INSTALL_DIR/$CONDA_ENV_NAME
CONDA_ENV_MANIFEST=${CONDA_ENV_INSTALL_DIR}/manifests/${CONDA_ENV_NAME}

rm -rf ${CONDA_ENV_MANIFEST}
mkdir -p ${CONDA_ENV_MANIFEST}

rm -rf ${ENVPREFIX}
mkdir -p ${ENVPREFIX}

export CONDA_PKGS_DIRS=${ENVPREFIX}/../.conda/pkgs
export PIP_CACHE_DIR=${ENVPREFIX}/../.pip

echo "Creating Conda environment with Python 3.12.8"
conda create python=3.12.8 --prefix ${ENVPREFIX} --override-channels \
           --channel https://software.repos.intel.com/python/conda/linux-64 \
           --channel conda-forge \
           --strict-channel-priority \
           --yes

conda activate ${ENVPREFIX}
echo "Conda is coming from $(which conda)"

# Use default modules on Sunspot with oneapi/2025.2.0 with PTI 0.12.3
module load cmake
unset CMAKE_ROOT
module load pti-gpu
module add hdf5

export CXX=$(which g++)
export CC=$(which gcc)

export REL_WITH_DEB_INFO=1
export USE_CUDA=0
export USE_ROCM=0
export USE_MKLDNN=1
export USE_MKL=1
export USE_ROCM=0
export USE_CUDNN=0
export USE_FBGEMM=0
export USE_NNPACK=0
export USE_QNNPACK=0
export USE_NCCL=0
export USE_CUDA=0
export BUILD_CAFFE2_OPS=0
export BUILD_TEST=0
export USE_DISTRIBUTED=1
export USE_NUMA=0
export USE_MPI=0
export _GLIBCXX_USE_CXX11_ABI=1
export USE_XPU=1
export USE_XCCL=1
export XPU_ENABLE_KINETO=1
export USE_ONEMKL=1
export USE_KINETO=1

export USE_AOT_DEVLIST='pvc'
export TORCH_XPU_ARCH_LIST='pvc'

export INTEL_MKL_DIR=$MKLROOT

TMP_WORK=/lus/flare/projects/datasets/softwares/envs/repositories/triton_xpu_git1b0418a9a_no_patch_11_07_2025
cd $TMP_WORK

mkdir -p ${CONDA_ENV_NAME}

#git clone git@github.com:intel/intel-xpu-backend-for-triton.git
cd intel-xpu-backend-for-triton/
#git checkout release/3.5.x
# commit 022968e53f6d65cd7aa3e3167b0a71c3b5f1465e (HEAD -> release/3.5.x, origin/release/3.5.x)
#git submodule sync && git submodule update --init --recursive

## installing PyTorch requirements
pip install --no-cache-dir -r $PYTORCH_REPO_DIR/requirements.txt

set +e

rm_conda_pkgs=(
        "dpcpp-cpp-rt"
        "impi_rt"
        "intel-cmplr-lib-rt"
        "intel-cmplr-lib-ur"
        "intel-cmplr-lic-rt"
        "intel-gpu-ocl-icd-system"
        "intel-opencl-rt"
        "intel-openmp"
        "intelpython"
        "intel-sycl-rt"
        "level-zero"
        "libedit"
        "mkl"
        "mkl_fft"
        "mkl_random"
        "mkl-service"
        "mkl_umath"
        "onemkl-sycl-blas"
        "onemkl-sycl-dft"
        "onemkl-sycl-lapack"
        "onemkl-sycl-rng"
        "onemkl-sycl-stats"
        "onemkl-sycl-vm"
        "pyedit"
        "tbb"
        "tcm"
        "umf"
        "tcmlib"
        "intel-pti"
        "impi-rt"
        "oneccl"
        "oneccl-devel"
        "onemkl-sycl-sparse"
        "numpy"
        "numpy-base"
    )

for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

pip uninstall -y numpy numpy-base
pip install --no-cache-dir numpy==2.3.4
#
## Install PyTorch_2.9.1a0+gitd29deef wheel
pip install --no-deps --no-cache-dir --force-reinstall $WHEELHOUSE_TMP/torch-*.whl
#
## Trying to use my build of llvm-project, git checkout f6ded0be897e2878612dd903f7e8bb85448269e5
#export LLVM_SYSPATH=/lus/flare/projects/datasets/softwares/envs/repositories/llvm_proj_gitf6ded0be_10_21_2025/llvm-project/build
#export LLVM_LIBRARY_DIR=/lus/flare/projects/datasets/softwares/envs/repositories/llvm_proj_gitf6ded0be_10_21_2025/llvm-project/build/lib
#export LLVM_INCLUDE_DIRS=/lus/flare/projects/datasets/softwares/envs/repositories/llvm_proj_gitf6ded0be_10_21_2025/llvm-project/build/include
#
# Trying an older, system installed LLVM
export LLVM_SYSPATH=/opt/aurora/25.190.0/spack/unified/0.10.1/install/linux-sles15-x86_64/gcc-13.3.0/llvm-develop-git.5708851-4ulhk4d
export LLVM_LIBRARY_DIR=/opt/aurora/25.190.0/spack/unified/0.10.1/install/linux-sles15-x86_64/gcc-13.3.0/llvm-develop-git.5708851-4ulhk4d/lib
export LLVM_INCLUDE_DIRS=/opt/aurora/25.190.0/spack/unified/0.10.1/install/linux-sles15-x86_64/gcc-13.3.0/llvm-develop-git.5708851-4ulhk4d/include
#
export TRITON_CODEGEN_BACKENDS=intel
export TRITON_OFFLINE_BUILD=ON
export TRITON_BUILD_PROTON=OFF
export TRITON_BUILD_PROTON_XPU=OFF
## Not setting the link-jobs for now
#export TRITON_PARALLEL_LINK_JOBS=16
export TRITON_BUILD_WITH_CCACHE=OFF

export TRITON_BUILD_NVIDIA_PLUGIN=OFF
export TRITON_BUILD_AMD_PLUGIN=OFF

export TRITON_APPEND_CMAKE_ARGS="
  -DLLVM_DIR=$LLVM_SYSPATH/lib/cmake/llvm
  -DMLIR_DIR=$LLVM_SYSPATH/lib/cmake/mlir
  -DLLD_DIR=$LLVM_SYSPATH/lib/cmake/lld
  -DLLVM_SYSPATH=$LLVM_SYSPATH
"

#echo "== LLVM_ROOT_DIR =="
#echo $LLVM_ROOT_DIR
#
#
## Install triton-xpu requirements
pip install --no-cache-dir -r python/requirements.txt

python setup.py clean

for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

pip uninstall -y numpy numpy-base
pip install --no-cache-dir numpy==2.3.4

DEBUG=1 python setup.py bdist_wheel --dist-dir ${TMP_WORK}/${CONDA_ENV_NAME} 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"triton_xpu-build-whl-$(tstamp).log"
echo "Finished building triton_xpu_3.5.0 for PyTorch 2.9.1 wheel with numpy 2.3.4 with oneapi/2025.2.0"
LOCAL_WHEEL_LOC=${TMP_WORK}/${CONDA_ENV_NAME}
pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/triton-*.whl 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"triton_xpu-install-$(tstamp).log"
echo "Finished installing the wheel and dependencies"

echo ""
echo "Writing the package lists"
conda list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_conda_env.list 2>&1
pip list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_pip.list 2>&1
echo "Package list writing finished"
