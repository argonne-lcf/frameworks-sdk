#!/bin/bash
#
#
## Load modules 2025.1.3 with PTI 0.10.3
module restore
module unload oneapi mpich
module use /soft/compilers/oneapi/2025.1.3/modulefiles
module use /soft/compilers/oneapi/nope/modulefiles
module add mpich/nope/develop-git.6037a7a
module load cmake
unset CMAKE_ROOT
export A21_SDK_PTIROOT_OVERRIDE=/home/cchannui/debug5/pti-gpu-test/tools/pti-gpu/d5c2e2e
module add oneapi/public/2025.1.3

CONDA_ENV_NAME=vLLM_Ratnam_pytorch_2p8_oneapi_2025p1p3_pti_0p10p3_python3p12

TMP_WORK=/lus/flare/projects/datasets/softwares/envs/manifests
cd $TMP_WORK

source /opt/aurora/24.347.0/spack/unified/0.9.2/install/linux-sles15-x86_64/gcc-13.3.0/miniforge3-24.3.0-0-gfganax/bin/activate
conda activate /lus/flare/projects/datasets/softwares/envs/${CONDA_ENV_NAME}

WHEEL_LOC=/lus/flare/projects/Aurora_deployment/datascience/software/envs/wheel_factory/vLLM_XCCL_Ratnam/vLLM_Ratnam_pytorch_2p8_oneapi_2025p1p3_pti_0p10p3_python3p12
pip install --no-cache-dir --no-deps --force-reinstall ${WHEEL_LOC}/vllm-*.whl
pip uninstall triton -y
#pip uninstall pytorch-triton-xpu -y
# pytorch_triton_xpu-3.3.0+git0bcc8265-cp310-cp310-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl
#pip3 install pytorch-triton-xpu==3.3.0+git0bcc8265 --index-url https://download.pytorch.org/whl/nightly/pytorch-triton-xpu/
#pip install https://download.pytorch.org/whl/nightly/pytorch_triton_xpu-3.3.0%2Bgit0bcc8265-cp310-cp310-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl

pip uninstall -y tcmlib intel-pti intel-cmplr-lic-rt intel-cmplr-lib-rt impi-rt umf tbb intel-opencl-rt \
    intel-cmplr-lib-ur intel-sycl-rt intel-openmp oneccl mkl dpcpp-cpp-rt onemkl-sycl-rng onemkl-sycl-dft \
    onemkl-sycl-blas oneccl-devel onemkl-sycl-sparse onemkl-sycl-lapack triton
export XPU_CCL_BACKEND="xccl"

mkdir -p ${CONDA_ENV_NAME}

conda list > ${TMP_WORK}/${CONDA_ENV_NAME}/${CONDA_ENV_NAME}_conda_env.list 2>&1

pip list > ${TMP_WORK}/${CONDA_ENV_NAME}/${CONDA_ENV_NAME}_pip.list 2>&1
