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
CONDA_ENV_NAME=vLLM_pytorch_2p8_oneapi_2025p1p1_pti_0p11p0_python3p10p14

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

# Load modules 2025.1.1 with PTI 0.11.0
module restore
module unload mpich oneapi
module use /soft/compilers/oneapi/2025.1.1/modulefiles
module use /soft/compilers/oneapi/nope/modulefiles
module add mpich/nope/develop-git.6037a7a
module add oneapi/public/2025.1.1

export CXX=$(which g++)
export CC=$(which gcc)

export REL_WITH_DEB_INFO=1

TMP_WORK=/lus/flare/projects/Aurora_deployment/datascience/software/envs/wheel_factory/vLLM_XCCL_Ratnam
cd $TMP_WORK

mkdir -p ${CONDA_ENV_NAME}

#git clone --branch ratnampa/vllm_with_xccl https://github.com/ratnampa/vllm.git
cd vllm
# torch-2.8.0.dev20250619+xpu-cp310-cp310-linux_x86_64.whl
pip3 install --pre torch==2.8.0.dev20250528+xpu --index-url https://download.pytorch.org/whl/nightly/xpu
pip install /flare/Aurora_deployment/intel/pytorch/soft/wheels/ipex/20250528/intel_extension_for_pytorch-2025.05-cp310-cp310-linux_x86_64.whl
pip install -v -r requirements/xpu.txt

pip uninstall -y tcmlib intel-pti intel-cmplr-lic-rt intel-cmplr-lib-rt impi-rt umf tbb intel-opencl-rt \
    intel-cmplr-lib-ur intel-sycl-rt intel-openmp oneccl mkl dpcpp-cpp-rt onemkl-sycl-rng onemkl-sycl-dft \
    onemkl-sycl-blas oneccl-devel onemkl-sycl-sparse onemkl-sycl-lapack triton

python setup.py clean
VLLM_TARGET_DEVICE=xpu python setup.py bdist_wheel --dist-dir ${TMP_WORK}/${CONDA_ENV_NAME} 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"vllm-build-whl-$(tstamp).log"
#pip uninstall triton -y
#pip3 install --pre pytorch-triton-xpu --index-url https://download.pytorch.org/whl/nightly/xpu
#export XPU_CCL_BACKEND="xccl"

