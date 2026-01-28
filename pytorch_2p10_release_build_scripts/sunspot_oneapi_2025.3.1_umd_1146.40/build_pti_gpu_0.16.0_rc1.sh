#!/bin/bash -x
#
# Build script for pti-gpu-0.16.0-rc1
#git clone https://github.com/intel/pti-gpu.git
#git checkout pti-0.16.0-rc1
#git submodule sync && git submodule update --init --recursive
#
# Time Stamp
tstamp() {
     date +"%Y-%m-%d-%H%M%S"
}

module restore
module unload mpich oneapi
module use /soft/compilers/oneapi/2025.3.1/modulefiles
module use /home/bertoni/modulefiles_mpich/
module add mpich/nope/5.0.0.aurora_test.3c70a61
module add oneapi/public/2025.3.1

module add cmake
unset CMAKE_ROOT


REPO_DIR=/lus/tegu/projects/datasets/software/26.26.0/wheelforge/repositories/pti_gpu_0.16.0_rc1_10_26_2026
LOG_FILE=${REPO_DIR}/pti-gpu-build-$(tstamp).log

touch ${LOG_FILE}
module -t list 2>&1 | tee ${LOG_FILE}


cd ${REPO_DIR}/pti-gpu/sdk
export PTIGPU_VERSION_HEAD=$(git rev-parse --short HEAD)
export PTIGPU_VERSION_DATE=$(date +"%Y%m%d")

mkdir build
cd build

cmake \
    -DCMAKE_INSTALL_PREFIX=${REPO_DIR}/pti-gpu-${PTIGPU_VERSION_DATE}-${PTIGPU_VERSION_HEAD} \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_TOOLCHAIN_FILE=${REPO_DIR}/pti-gpu/sdk/cmake/toolchains/icpx_toolchain.cmake \
    -DPTI_BUILD_SAMPLES=OFF \
    ..
make -j51
make install 2>&1 | tee ${LOG_FILE}

