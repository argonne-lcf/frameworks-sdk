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
CONDA_ENV_NAME=torchvision_0p22p1_oneapi_2025p1p3_pti_0p10p3_python3p10p14

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
           --insecure \
           --strict-channel-priority \
           --yes

conda activate ${ENVPREFIX}

echo "Conda is coming from $(which conda)"

# Load modules 2025.1.3 with PTI 0.10.3
module restore
module unload oneapi mpich
module use /soft/compilers/oneapi/2025.1.3/modulefiles
module use /soft/compilers/oneapi/nope/modulefiles
module add mpich/nope/develop-git.6037a7a
module load cmake
unset CMAKE_ROOT
export A21_SDK_PTIROOT_OVERRIDE=/home/cchannui/debug5/pti-gpu-test/tools/pti-gpu/d5c2e2e
module add oneapi/public/2025.1.3

TMP_WORK=/lus/flare/projects/Aurora_deployment/datascience/software/envs/wheel_factory/torchvision_0p22p1
cd $TMP_WORK

PYTORCH_WHEEL_LOC=/lus/flare/projects/Aurora_deployment/datascience/software/envs/wheel_factory/pytorch_2p7/pt2p7_py3p10p14_pti0p10p3
IPEX_WHEEL_LOC=/lus/flare/projects/Aurora_deployment/datascience/software/envs/wheel_factory/ipex_2p7/ipex_2p7_oneapi_2025p1p3_pti_0p10p3_python3p10p14_panos
TORCH_CCL_WHEEL_LOC=/lus/flare/projects/Aurora_deployment/datascience/software/envs/wheel_factory/torch_ccl_2p7/torch_ccl_2p7_oneapi_2025p1p3_pti_0p10p3_python3p10p14
#pip install --no-cache-dir -r ${PYTORCH_WHEEL_LOC}/pytorch_2p7_requirements_modified.txt
pip install --no-cache-dir -r ${IPEX_WHEEL_LOC}/torchvision_ipex_pytorch_2p7_combined_requirements.txt
pip uninstall -y numpy
pip install --no-cache-dir numpy==1.26.4
pip install --no-deps --no-cache-dir --force-reinstall $PYTORCH_WHEEL_LOC/torch-*.whl
pip install --no-deps --no-cache-dir --force-reinstall $IPEX_WHEEL_LOC/intel_extension_for_pytorch-*.whl
pip install --no-deps --no-cache-dir --force-reinstall $TORCH_CCL_WHEEL_LOC/oneccl_bind_pt-*.whl

mkdir -p ${CONDA_ENV_NAME}
cd vision/

export CXX=$(which g++)
echo "g++ = $CXX"
export CC=$(which gcc)
echo "CC = $CC"

export PYTORCH_VERSION=2.7.1
export TORCH_CUDA_ARCH_LIST=""
export FORCE_CUDA=0
export USE_CUDA=0
export USE_PNG=1
export USE_JPEG=1
export USE_WEBP=1
export IS_ROCM=0
export BUILD_CUDA_SOURCES=0

pip uninstall -y mkl mkl-include

python setup.py clean
python setup.py bdist_wheel --dist-dir ${TMP_WORK}/${CONDA_ENV_NAME} 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"torchvision-build-whl-$(tstamp).log"

echo ""
echo "Completed build torchvision wheel" 
echo ""

