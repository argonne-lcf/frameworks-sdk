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
CONDA_ENV_INSTALL_DIR=/lus/tegu/projects/datasets/software/26.26.0/wheelforge/envs/conda_envs
CONDA_ENV_NAME=triton_xpu_3.6.0_pytorch_2.10.0_rel_oneapi_2025.3.1_numpy_2.2.6_python_3.12.8

WHEELHOUSE_TMP=/lus/tegu/projects/datasets/software/26.26.0/wheelhouse
PYTORCH_REPO_DIR=/lus/tegu/projects/datasets/software/26.26.0/wheelforge/repositories/pytorch_2.10.0_01_27_2026/pytorch

module add miniforge3/25.3.0-3
source $MINIFORGE3_ROOT/bin/activate
# The line above does exactly the line below
#source /opt/aurora/26.26.0/spack/unified/1.1.1/install/linux-x86_64/miniforge3-25.3.0-3-w5hoacg/bin/activate

ENVPREFIX=$CONDA_ENV_INSTALL_DIR/$CONDA_ENV_NAME
CONDA_ENV_MANIFEST=${CONDA_ENV_INSTALL_DIR}/manifests/${CONDA_ENV_NAME}

rm -rf ${ENVPREFIX}
mkdir -p ${ENVPREFIX}

rm -rf ${CONDA_ENV_MANIFEST}
mkdir -p ${CONDA_ENV_MANIFEST}

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

# Use default modules on Aurora with oneapi/2025.3.1 with PTI 0.16.0-rc1
module add cmake
unset CMAKE_ROOT
module add ninja
module add pti-gpu
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

TMP_WORK=/lus/tegu/projects/datasets/software/26.26.0/wheelforge/repositories/triton_xpu_3.6.0_01_28_2026
cd $TMP_WORK

mkdir -p ${CONDA_ENV_NAME}

LOG_FILE=${TMP_WORK}/${CONDA_ENV_NAME}/module-$(tstamp).log

touch ${LOG_FILE}
module -t list 2>&1 | tee ${LOG_FILE}

#git clone git@github.com:intel/intel-xpu-backend-for-triton.git
cd intel-xpu-backend-for-triton
#git checkout v3.6.0
#git submodule sync && git submodule update --init --recursive

# Installing a couple of portability tools
pip install conda-pack ipython 

## installing PyTorch requirements
pip install --no-cache-dir -r ${PYTORCH_REPO_DIR}/requirements.txt

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
        "numpy"
        "numpy-base"
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
        "nvidia-nccl-cu12"
        "mlflow-tracing"
    )

for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

pip uninstall -y numpy
pip install --no-cache-dir numpy==2.2.6

## Install 2.10.0a0+git449b176 wheel
pip install --no-deps --no-cache-dir --force-reinstall $WHEELHOUSE_TMP/torch-*.whl

# Trying system installed LLVM
export LLVM_SYSPATH=/opt/aurora/26.26.0/spack/unified/1.1.1/install/linux-x86_64/llvm-develop-git.f6ded0b-dk75ija
export LLVM_LIBRARY_DIR=/opt/aurora/26.26.0/spack/unified/1.1.1/install/linux-x86_64/llvm-develop-git.f6ded0b-dk75ija/lib
export LLVM_INCLUDE_DIRS=/opt/aurora/26.26.0/spack/unified/1.1.1/install/linux-x86_64/llvm-develop-git.f6ded0b-dk75ija/include

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
## Install triton-xpu requirements
pip install --no-cache-dir -r python/requirements.txt

## pyelftools is required, but not included in the requirements file!
pip install --no-cache-dir pyelftools

python setup.py clean

for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

#make triton
# The following is the correct version of triton-xpu
# https://github.com/pytorch/pytorch/blob/release/2.10.0/.ci/docker/triton_xpu_version.txt
#pip install --no-cache-dir pytorch-triton-xpu==3.6.0 --index-url https://download.pytorch.org/whl/nightly/
# Skipping triton for the first iteration. We will try to build from source.
# If fails, we will fall back to the pre-built binary

pip install --no-cache-dir numpy==2.2.6

DEBUG=1 python setup.py bdist_wheel --dist-dir ${TMP_WORK}/${CONDA_ENV_NAME} 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"triton_xpu-build-whl-$(tstamp).log"
echo "Finished building triton_xpu_3.6.0 for PyTorch 2.9.1 wheel with numpy 2.2.6 with oneapi/2025.3.1"
LOCAL_WHEEL_LOC=${TMP_WORK}/${CONDA_ENV_NAME}
pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/triton-*.whl 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"triton_xpu-install-$(tstamp).log"
echo "Finished installing the wheel and dependencies"

echo ""
echo "Writing the package lists"
conda list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_conda_env.list 2>&1
pip list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_pip.list 2>&1
echo "Package list writing finished"

echo "Writing $CONDA_ENV_MANIFEST/${CONA_ENV_NAME}_all.list"
cat $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_conda_env.list | grep -v '^#' | grep 'pypi$' | perl -pe 's/^(\S+)\s+(\S+).*/$1==$2/' >  $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_all.list

 
