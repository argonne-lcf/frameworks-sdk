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
CONDA_ENV_NAME=ipex_2p8_oneapi_2025p2p0_pti_0p10p3_numpy_2p0p2_python3p10p14

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
#module load cmake
#unset CMAKE_ROOT
export A21_SDK_PTIROOT_OVERRIDE=/home/cchannui/debug5/pti-gpu-test/tools/pti-gpu/d5c2e2e
module add oneapi/public/2025.2.0

TMP_WORK=/lus/flare/projects/Aurora_deployment/datascience/software/envs/wheel_factory/ipex_2p8_07.11.2025
cd $TMP_WORK

LOCAL_WHEEL_LOC=/lus/flare/projects/Aurora_deployment/datascience/software/envs/wheel_factory/pytorch_2p8_07.10.2025/pytorch_2p8_rc4_oneapi_2025p2p0_pti_0p10p3_numpy_2p0p2_python3p10p14
pip install --no-cache-dir -r ${LOCAL_WHEEL_LOC}/ipex_pytorch_2p8_combined_requirements.txt
pip uninstall -y numpy
pip install --no-cache-dir numpy==2.0.2
pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/torch-*.whl

mkdir -p ${CONDA_ENV_NAME}
cd intel-extension-for-pytorch/

export CMAKE_PREFIX_PATH="${CONDA_PREFIX:-'$(dirname $(which conda))/../'}:${CMAKE_PREFIX_PATH}"

export DPCPP_ROOT=$(realpath $(dirname $(which icpx))/..)
export CXX=$(which g++)
export CC=$(which gcc)

export BUILD_DOUBLE_KERNEL=ON
export MKL_DPCPP_ROOT=${MKLROOT}
export USE_ITT_ANNOTATION=ON
export BUILD_WITH_CPU=ON
export _GLIBCXX_USE_CXX11_ABI=1
export TORCH_DEVICE_BACKEND_AUTOLOAD=0
export USE_AOT_DEVLIST="pvc"
export TORCH_XPU_ARCH_LIST="pvc"

pip uninstall -y mkl mkl-include

python setup.py clean
python setup.py bdist_wheel --dist-dir ${TMP_WORK}/${CONDA_ENV_NAME} 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"ipex-build-whl-$(tstamp).log"
