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
CONDA_ENV_INSTALL_DIR=/lus/flare/projects/datasets/softwares/envs
CONDA_ENV_NAME=vLLM_main_pytorch_2p8_oneapi_2025p1p3_pti_0p10p3_python3p10_julia

source /opt/aurora/24.347.0/spack/unified/0.9.2/install/linux-sles15-x86_64/gcc-13.3.0/miniforge3-24.3.0-0-gfganax/bin/activate
ENVPREFIX=$CONDA_ENV_INSTALL_DIR/$CONDA_ENV_NAME
rm -rf ${ENVPREFIX}
mkdir -p ${ENVPREFIX}

export CONDA_PKGS_DIRS=${ENVPREFIX}/../.conda/pkgs
export PIP_CACHE_DIR=${ENVPREFIX}/../.pip

echo "Creating Conda environment with Python 3.10"
conda create python=3.10 --prefix ${ENVPREFIX} --override-channels \
           --channel conda-forge \
           --strict-channel-priority \
           --solver=libmamba \
           --yes

conda activate ${ENVPREFIX}
echo "Conda is coming from $(which conda)"

# Load modules 2025.1.3 with PTI 0.10.3
module restore
module unload mpich oneapi
module use /soft/compilers/oneapi/nope/modulefiles
module use /soft/compilers/oneapi/2025.1.3/modulefiles
module use /soft/preview/components/graphics-compute-runtime/1099.17/modulefiles
module add mpich/nope/develop-git.6037a7a
module add oneapi/public/2025.1.3
module add graphics-compute-runtime/1099.17

export CCL_KVS_MODE=mpi
export CCL_KVS_CONNECTION_TIMEOUT=600

export ZE_FLAT_DEVICE_HIERARCHY=FLAT
export ZE_ENABLE_PCI_ID_DEVICE_ORDER=1

export FI_PROVIDER="cxi,tcp;ofi_rxm"
export FI_CXI_OFLOW_BUF_SIZE=8388608
export FI_CXI_DEFAULT_CQ_SIZE=1048576
export FI_CXI_CQ_FILL_PERCENT=30
export FI_MR_CACHE_MONITOR=disabled
export FI_MR_ZE_CACHE_MONITOR_ENABLED=0

export PALS_PMI=pmix

export CXX=$(which g++)
export CC=$(which gcc)

export REL_WITH_DEB_INFO=1

TMP_WORK=/lus/flare/projects/datasets/softwares/envs/ext_repos/vllm_07.15.2025
cd $TMP_WORK

#rm -rf ${CONDA_ENV_NAME}
mkdir -p ${CONDA_ENV_NAME}

#git clone --branch ratnampa/vllm_with_xccl https://github.com/ratnampa/vllm.git
cd vllm

pip install --pre torch==2.8.0.dev20250528+xpu --index-url https://download.pytorch.org/whl/nightly/xpu
pip install --pre torchvision==0.22.0.dev20250528+xpu --index-url https://download.pytorch.org/whl/nightly/xpu
pip install /flare/Aurora_deployment/intel/pytorch/soft/wheels/ipex/20250528/intel_extension_for_pytorch-2025.05-cp310-cp310-linux_x86_64.whl

pip install outlines==0.1.11 --no-deps
pip install -r requirements/xpu.txt

pip uninstall -y tcmlib intel-pti intel-cmplr-lic-rt intel-cmplr-lib-rt impi-rt umf tbb intel-opencl-rt intel-cmplr-lib-ur intel-sycl-rt intel-openmp oneccl mkl dpcpp-cpp-rt onemkl-sycl-rng onemkl-sycl-dft onemkl-sycl-blas oneccl-devel onemkl-sycl-sparse onemkl-sycl-lapack triton pytorch-triton pytorch-triton-xpu

pip install --no-cache-dir pytorch-triton-xpu==3.3.1+gitb0e26b73 --index-url https://download.pytorch.org/whl/nightly/xpu
#pip install --pre pytorch-triton-xpu --index-url https://download.pytorch.org/whl/nightly/xpu

python setup.py clean
VLLM_TARGET_DEVICE=xpu python setup.py bdist_wheel --dist-dir ${TMP_WORK}/${CONDA_ENV_NAME} 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"vllm-build-whl-$(tstamp).log"
pip install  --no-deps --force-reinstall ${TMP_WORK}/${CONDA_ENV_NAME}/vllm-*.whl 
#pip uninstall triton -y
#pip3 install --pre pytorch-triton-xpu --index-url https://download.pytorch.org/whl/nightly/xpu
#export XPU_CCL_BACKEND="xccl"

