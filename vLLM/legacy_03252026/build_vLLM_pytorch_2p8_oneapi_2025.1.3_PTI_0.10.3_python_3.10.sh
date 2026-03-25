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
CONDA_ENV_NAME=vLLM_Ratnam_pytorch_2p8_oneapi_2025p1p3_pti_0p10p3_python3p10

source /opt/aurora/24.347.0/spack/unified/0.9.2/install/linux-sles15-x86_64/gcc-13.3.0/miniforge3-24.3.0-0-gfganax/bin/activate
ENVPREFIX=$CONDA_ENV_INSTALL_DIR/$CONDA_ENV_NAME
#rm -rf ${ENVPREFIX}
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

# Set +e to remove error if package is not already installed.  We want to continue
# and not abort the rest of the installation script
set +e
#rm_conda_pkgs=("impi_rt" "intel-opencl-rt" "pyedit" "level-zero" "mkl" "mkl-service" "mkl_fft" "mkl_random" "mkl_umath" "intel-cmplr-lib-rt" "intel-cmplr-lib-ur" "intel-sycl-rt" "tcm" "umf" "numpy" "numpy-base")
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
    )

for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

# Load modules 2025.1.3 with PTI 0.10.3
module restore
module unload oneapi mpich
module use /soft/compilers/oneapi/nope/modulefiles
module use /soft/compilers/oneapi/2025.1.3/modulefiles
module use /soft/preview/components/graphics-compute-runtime/1099.17/modulefiles
module add mpich/nope/develop-git.6037a7a
module load cmake
unset CMAKE_ROOT
export A21_SDK_PTIROOT_OVERRIDE=/home/cchannui/debug5/pti-gpu-test/tools/pti-gpu/d5c2e2e
module add oneapi/public/2025.1.3
module add graphics-compute-runtime/1099.17

export CXX=$(which g++)
export CC=$(which gcc)

export REL_WITH_DEB_INFO=1

TMP_WORK=/lus/flare/projects/Aurora_deployment/datascience/software/envs/wheel_factory/vLLM_XCCL_Ratnam
cd $TMP_WORK

mkdir -p ${CONDA_ENV_NAME}

LOCAL_WHEEL_LOC=/lus/flare/projects/datasets/wheelforge/pytorch_2p8_oneapi_2025p1p3_python_3p10

#git clone --branch ratnampa/vllm_with_xccl https://github.com/ratnampa/vllm.git
cd vllm
pip install --no-cache-dir -r ${CONDA_ENV_INSTALL_DIR}/torchvision_triton_xpu_ipex_pytorch_2p8_combined_for_vllm_requirements.txt

pip uninstall -y numpy
pip install --no-cache-dir numpy==2.0.2
pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/torch-*.whl
pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/intel_extension_for_pytorch-*.whl
pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/torchvision-*.whl
pip install --no-deps --no-cache-dir --force-reinstall pytorch-triton-xpu==3.3.1+gitb0e26b73 --index-url https://download.pytorch.org/whl/nightly/

pip install -v --no-cache-dir -r requirements/xpu.txt

pip uninstall triton pytorch-triton pytorch-triton-xpu -y

pip uninstall -y tcmlib intel-pti intel-cmplr-lic-rt intel-cmplr-lib-rt impi-rt umf tbb intel-opencl-rt \
    intel-cmplr-lib-ur intel-sycl-rt intel-openmp oneccl mkl dpcpp-cpp-rt onemkl-sycl-rng onemkl-sycl-dft \
    onemkl-sycl-blas oneccl-devel onemkl-sycl-sparse onemkl-sycl-lapack triton

for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

pip uninstall -y numpy
pip install --no-cache-dir numpy==2.0.2

pip install --no-deps --no-cache-dir --force-reinstall pytorch-triton-xpu==3.3.1+gitb0e26b73 --index-url https://download.pytorch.org/whl/nightly/

python setup.py clean
VLLM_TARGET_DEVICE=xpu python setup.py bdist_wheel --dist-dir ${TMP_WORK}/${CONDA_ENV_NAME} 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"vllm-build-whl-$(tstamp).log"
#pip uninstall triton -y
#pip3 install --pre pytorch-triton-xpu --index-url https://download.pytorch.org/whl/nightly/xpu
export XPU_CCL_BACKEND="xccl"

