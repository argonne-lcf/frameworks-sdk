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
CONDA_ENV_NAME=ipex_2.9.10+xpu_oneapi_2025.2.0_pti_0.12.3_numpy_2.3.4_python3.12.8

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

# Load modules 2025.2.0 with PTI 0.12.3
module load cmake
unset CMAKE_ROOT
module load pti-gpu
module load hdf5


TMP_WORK=/lus/flare/projects/datasets/softwares/envs/repositories/ipex_v2.9.10+xpu_11_06_2025
cd $TMP_WORK

LOCAL_WHEEL_LOC=${WHEELHOUSE_TMP}
pip install --no-cache-dir -r ${LOCAL_WHEEL_LOC}/ipex_2.9.10_pytorch_2.9.1_combined_requirements.txt

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
pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/torch-*.whl

for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

mkdir -p ${CONDA_ENV_NAME}

# git clone git@github.com:intel/intel-extension-for-pytorch.git
cd intel-extension-for-pytorch/
# git checkout v2.9.10+xpu
# HEAD is now at 7259fd81b use seqlen k only for cases with block table (#5836) (#5839)
# git submodule sync && git submodule update --init --recursive

#export CMAKE_PREFIX_PATH="${CONDA_PREFIX:-'$(dirname $(which conda))/../'}:${CMAKE_PREFIX_PATH}"

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

export CXXFLAGS="$CXXFLAGS -Wno-all -w"
export CFLAGS="$CFLAGS -Wno-all -w"

pip uninstall -y mkl mkl-include
pip uninstall -y numpy numpy-base
pip install --no-cache-dir numpy==2.3.4

python setup.py clean --all
python setup.py bdist_wheel --dist-dir ${TMP_WORK}/${CONDA_ENV_NAME} 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"ipex-build-whl-$(tstamp).log"

echo "Finished building IPEX-2.9.10+xpu release wheel for PyTorch-2.9.1 with oneapi/2025.2.0, PTI-0.12.3, and numpy-2.3.4"

IPEX_WHEEL_LOC=${TMP_WORK}/${CONDA_ENV_NAME}
pip install --no-deps --no-cache-dir --force-reinstall $IPEX_WHEEL_LOC/intel_extension_for_pytorch-*.whl 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"ipex-install-$(tstamp).log"
echo "Finished installing the IPEX wheel and dependencies"

echo ""
echo "Writing the package lists"
conda list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_conda_env.list 2>&1
pip list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_pip.list 2>&1
echo "Package list writing finished"
