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
CONDA_ENV_INSTALL_DIR=/lus/flare/projects/datasets/softwares/envs/conda_envs
CONDA_ENV_NAME=torchvision_0.24.0_oneapi_2025.2.0_pti_0.12.3_numpy_2.3.4_python3.12.8

WHEELHOUSE_TMP=/lus/flare/projects/datasets/softwares/envs/wheelhouse_tmp/vllm_gpt_oss

source /opt/aurora/25.190.0/spack/unified/0.10.1/install/linux-sles15-x86_64/gcc-13.3.0/miniforge3-24.3.0-0-gfganax/bin/activate

ENVPREFIX=$CONDA_ENV_INSTALL_DIR/$CONDA_ENV_NAME
CONDA_ENV_MANIFEST=${CONDA_ENV_INSTALL_DIR}/manifests/${CONDA_ENV_NAME}

rm -rf ${CONDA_ENV_MANIFEST}
mkdir -p ${CONDA_ENV_MANIFEST}

rm -rf ${ENVPREFIX}
mkdir -p ${ENVPREFIX}

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

# Load default modules with oneapi/2025.2.0 with PTI 0.12.3 on Aurora
module restore
module load cmake
unset CMAKE_ROOT
module load pti-gpu
module load hdf5

TMP_WORK=/lus/flare/projects/datasets/softwares/envs/repositories/torchvision_0.24.0_11_06_2025
cd $TMP_WORK

LOCAL_WHEEL_LOC=${WHEELHOUSE_TMP}

pip install --no-cache-dir -r ${LOCAL_WHEEL_LOC}/torchvision_0.24.0_ipex_2.9.10_pytorch_2.9.1_combined_requirements.txt

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
    )

for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

pip uninstall -y numpy numpy-base
pip install --no-cache-dir numpy==2.3.4
pip install --no-cache-dir pytorch-triton-xpu==3.5.0 --index-url https://download.pytorch.org/whl/

for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/torch-*.whl
pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/intel_extension_for_pytorch-*.whl

mkdir -p ${CONDA_ENV_NAME}

#git clone git@github.com:pytorch/vision.git
cd vision/
#git checkout v0.24.0
#git submodule sync && git submodule update --init --recursive

export CXX=$(which g++)
echo "g++ = $CXX"
export CC=$(which gcc)
echo "CC = $CC"

export PYTORCH_VERSION=2.8.0
export TORCH_CUDA_ARCH_LIST=""
export FORCE_CUDA=0
export USE_CUDA=0
export USE_PNG=1
export USE_JPEG=1
export USE_WEBP=1
export IS_ROCM=0
export BUILD_CUDA_SOURCES=0

pip uninstall -y mkl mkl-include

python setup.py clean --all
python setup.py bdist_wheel --dist-dir ${TMP_WORK}/${CONDA_ENV_NAME} 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"torchvision-build-whl-$(tstamp).log"

echo ""
echo "Completed build torchvision/0.24.0 wheel with oneapi/2025.2.0 with PyTorch 2.9.1, IPEX 2.9.10+xpu, PTI/0.12.3 and numpy/2.3.4" 
echo ""

TORCHVISION_WHEEL_LOC=${TMP_WORK}/${CONDA_ENV_NAME}
pip install --no-deps --no-cache-dir --force-reinstall $TORCHVISION_WHEEL_LOC/torchvision-*.whl 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"torchvision-install-$(tstamp).log"
echo ""
echo "Finished installing the torchvision wheel and dependencies"
echo ""

echo ""
echo "Writing the package lists"
conda list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_conda_env.list 2>&1
pip list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_pip.list 2>&1
echo "Package list writing finished"
