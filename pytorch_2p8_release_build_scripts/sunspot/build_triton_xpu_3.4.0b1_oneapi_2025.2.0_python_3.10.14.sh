#!/bin/bash -x
#
# For this build of triton-xpu I changed the following file
# https://github.com/intel/intel-xpu-backend-for-triton/blob/v3.4.0b1/scripts/compile-triton.sh
# and the following lines; added line 184 to produce a wheel and then run the 
# full installation process
#  pip wheel --wheel-dir ${TRITON_PROJ} -v -e '.[build,tests]'
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
CONDA_ENV_INSTALL_DIR=/lus/tegu/projects/datasets/software/wheelforge/envs/conda_envs/triton_xpu_3.4.10b1_build_base
CONDA_ENV_NAME=triton_xpu_3.4.0b1_oneapi_2025.2.0_python3.10.14

source /opt/aurora/25.190.0/spack/unified/0.10.0/install/linux-sles15-x86_64/gcc-13.3.0/miniforge3-24.3.0-0-gfganax/bin/activate
ENVPREFIX=$CONDA_ENV_INSTALL_DIR/$CONDA_ENV_NAME
rm -rf ${ENVPREFIX}
mkdir -p ${ENVPREFIX}

export BASE=${CONDA_ENV_INSTALL_DIR}
export PACKAGES_DIR=$BASE/packages
export LLVM_PROJ=$BASE/llvm
export LLVM_PROJ_BUILD=$LLVM_PROJ/build
export TRITON_PROJ=/lus/tegu/projects/datasets/software/wheelforge/repositories/triton_xpu_v3p4p0b1
export TRITON_PROJ_BUILD=$TRITON_PROJ/build

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

# Go with the default modules on Sunspot
#
module load cmake
unset CMAKE_ROOT

pip install ninja wheel pybind11

export REL_WITH_DEB_INFO=1

TMP_WORK=${TRITON_PROJ}
cd $TMP_WORK

mkdir -p ${CONDA_ENV_NAME}

source ${TRITON_PROJ}/intel-xpu-backend-for-triton/scripts/compile-triton.sh --llvm --triton --clean 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"triton-xpu-build-whl-$(tstamp).log"
