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
CONDA_ENV_INSTALL_DIR=/lus/flare/projects/Aurora_deployment/datascience/software/envs/conda_envs
CONDA_ENV_NAME=pytorch_2p8_rc4_oneapi_2025p2p0_pti_0p10p3_numpy_2p0p2_python3p10p14

source /opt/aurora/24.347.0/spack/unified/0.9.2/install/linux-sles15-x86_64/gcc-13.3.0/miniforge3-24.3.0-0-gfganax/bin/activate
ENVPREFIX=$CONDA_ENV_INSTALL_DIR/$CONDA_ENV_NAME
rm -rf ${ENVPREFIX}
mkdir -p ${ENVPREFIX}

export CONDA_PKGS_DIRS=${ENVPREFIX}/../.conda/pkgs
export PIP_CACHE_DIR=${ENVPREFIX}/../.pip

echo "Creating Conda environment with Python 3.10.14"
conda create python=3.10.14 --prefix ${ENVPREFIX} --override-channels \
           --channel https://software.repos.intel.com/python/conda/linux-64 \
           --channel conda-forge \
           --strict-channel-priority \
           --yes

conda activate ${ENVPREFIX}
echo "Conda is coming from $(which conda)"

# Load modules 2025.2.0 with PTI 0.10.3
module restore
module unload oneapi mpich
module use /soft/compilers/oneapi/nope/modulefiles
module use /soft/compilers/oneapi/2025.2.0/modulefiles
module add mpich/nope/develop-git.6037a7a
module load cmake
unset CMAKE_ROOT
export A21_SDK_PTIROOT_OVERRIDE=/home/cchannui/debug5/pti-gpu-test/tools/pti-gpu/d5c2e2e
module add oneapi/public/2025.2.0

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

TMP_WORK=/lus/flare/projects/Aurora_deployment/datascience/software/envs/wheel_factory/pytorch_2p8_07.10.2025
cd $TMP_WORK

mkdir -p ${CONDA_ENV_NAME}

#git clone https://github.com/pytorch/pytorch.git
cd pytorch
#git checkout v2.8.0-rc4
#git submodule sync && git submodule update --init --recursive

pip install --no-cache-dir -r requirements.txt

pip uninstall -y numpy
pip install --no-cache-dir numpy==2.0.2

python setup.py clean
make triton
#pip install --no-cache-dir pytorch-triton-xpu==3.4.0+gitae324eea --index-url https://download.pytorch.org/whl/nightly/
MAX_JOBS=32 python setup.py bdist_wheel --dist-dir ${TMP_WORK}/${CONDA_ENV_NAME} 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"torch-build-whl-$(tstamp).log"
