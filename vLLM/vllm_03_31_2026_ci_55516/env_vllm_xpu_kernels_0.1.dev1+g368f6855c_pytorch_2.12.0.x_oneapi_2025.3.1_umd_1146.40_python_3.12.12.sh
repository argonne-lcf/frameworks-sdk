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
CONDA_ENV_NAME=vllm_03312026_oneapi_2025.3.1_umd_1146.40_py_3.12.12

WHEELHOUSE_TMP=/lus/flare/projects/datasets/softwares/envs/wheelhouse_tmp/vllm_03_31_2026_ci_55516
#PYTORCH_REPO_DIR=/lus/tegu/projects/datasets/software/26.26.0/wheelforge/repositories/pytorch_2.10.0_01_27_2026/pytorch

## Miniforge conda base environment
source /opt/aurora/26.26.0/spack/unified/1.1.1/install/linux-x86_64/miniforge3-25.11.0-1-khkcc6i/bin/activate

ENVPREFIX=$CONDA_ENV_INSTALL_DIR/$CONDA_ENV_NAME
CONDA_ENV_MANIFEST=${CONDA_ENV_INSTALL_DIR}/manifests/${CONDA_ENV_NAME}

rm -rf ${ENVPREFIX}
mkdir -p ${ENVPREFIX}

rm -rf ${CONDA_ENV_MANIFEST}
mkdir -p ${CONDA_ENV_MANIFEST}

export CONDA_PKGS_DIRS=${ENVPREFIX}/../.conda/pkgs
export PIP_CACHE_DIR=${ENVPREFIX}/../.pip

echo "Creating Conda environment with Python 3.12.12"
conda create python=3.12.12 icu=73 --prefix ${ENVPREFIX} --override-channels \
           --channel conda-forge \
           --strict-channel-priority \
           --yes

conda activate ${ENVPREFIX}
echo "Conda is coming from $(which conda)"

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
        "tcmlib"
        "intel-pti"
        "impi-rt"
        "oneccl"
        "oneccl-devel"
        "onemkl-sycl-sparse"
        "nvidia-nccl-cu12"
        "mlflow-tracing"
        "onemkl-license"
        "mkl"
        "mkl-include"
        "mkl-static"
        "bzip2"
        "icu"
        "libgcc"
        "libgcc-ng"
        "libgomp"
        "liblzma"
        "libnsl"
        "libstdcxx"
        "libuuid"
        "libxcrypt"
        "ncurses"
    )

for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

# Use default modules on Aurora with oneapi/2025.3.1 with PTI 0.16.0-rc1
module add cmake
unset CMAKE_ROOT
module add ninja
module add pti-gpu
module add hdf5

TMP_WORK=/lus/flare/projects/datasets/softwares/envs/tmpdir_for_envs
cd $TMP_WORK

mkdir -p ${CONDA_ENV_NAME}

LOG_FILE=${TMP_WORK}/${CONDA_ENV_NAME}/module-$(tstamp).log

touch ${LOG_FILE}
module -t list 2>&1 | tee ${LOG_FILE}

# Installing a couple of portability tools
pip install conda-pack ipython 

## installing pytorch and triton-xpu requirements
pip install --no-cache-dir -r ${WHEELHOUSE_TMP}/torchvision_0.27.0a0+git9bf794dd6f_triton_3.7.1+git5711ee7f_pytorch_2.12.0a0+git571aaf5_requirements.txt

for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

pip uninstall -y numpy numpy-base
pip install --no-cache-dir numpy==2.2.6

## Install PyTorch 2.10.0a0+git449b176 wheel
## Install triton-xpu 3.6.0+git225cdbde wheel
pip install --no-deps --no-cache-dir --force-reinstall $WHEELHOUSE_TMP/torch-*.whl
pip install --no-deps --no-cache-dir --force-reinstall $WHEELHOUSE_TMP/triton-*.whl
pip install --no-deps --no-cache-dir --force-reinstall $WHEELHOUSE_TMP/torchvision-*.whl
pip install --no-deps --no-cache-dir --force-reinstall $WHEELHOUSE_TMP/mpi4py-*.whl

export CXX=$(which g++)
export CC=$(which gcc)

export _GLIBCXX_USE_CXX11_ABI=1

#export PYTORCH_VERSION=2.10.0
export TORCH_CUDA_ARCH_LIST=""
export FORCE_CUDA=0
export USE_CUDA=0
export USE_PNG=1
export USE_JPEG=1
export USE_WEBP=1
export IS_ROCM=0
export BUILD_CUDA_SOURCES=0

for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

pip uninstall -y mkl mkl-include onemkl-license
pip uninstall -y numpy numpy-base
pip install --no-cache-dir numpy==2.2.6
##
## vLLM Stuff
##
pip install outlines_core==0.2.11 --no-deps
pip install --no-cache-dir -r ${WHEELHOUSE_TMP}/vllm_xpu_separate_requirements.txt

for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

pip uninstall -y mkl mkl-include onemkl-license mkl-static
pip uninstall -y numpy numpy-base
pip install --no-cache-dir numpy==2.2.6

## vllm's complex inter-dependency sometimes brings own triton, triton-xpu
pip uninstall -y triton pytorch-triton pytorch-triton-xpu

## Installing back our triton-xpu wheel
pip install --no-deps --no-cache-dir --force-reinstall $WHEELHOUSE_TMP/triton-*.whl

## Installing vllm-xpu-kernels wheel
pip install --no-deps --no-cache-dir --force-reinstall --no-build-isolation $WHEELHOUSE_TMP/vllm_xpu_kernels-*.whl

## Installing vLLM wheel
pip install --no-deps --no-cache-dir --force-reinstall --no-build-isolation $WHEELHOUSE_TMP/vllm-*.whl

## Updating transformers to the latest -- as vllm-xpu-kernels want it, and
## vllm seems not to break, although requirements wants < 5.0.0
pip uninstall -y transformers
pip install transformers==5.4.0
# Last round of cleanup
for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

pip uninstall -y mkl mkl-include onemkl-license mkl-static
pip uninstall -y numpy numpy-base
pip install --no-cache-dir numpy==2.2.6
#
echo "Finished installing the vllm_03312026 and vllm_xpu_kernels_03312026 wheels and dependencies"

echo ""
echo "Writing the package lists"
echo "Writing $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_conda_env.list"
conda list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_conda_env.list 2>&1
echo "Writing $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_pip.list" 
pip list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_pip.list 2>&1
echo "Package list writing finished"

echo "Writing $CONDA_ENV_MANIFEST/${CONA_ENV_NAME}_all.list"
cat $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_conda_env.list | grep -v '^#' | grep 'pypi$' | perl -pe 's/^(\S+)\s+(\S+).*/$1==$2/' >  $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_all.list

 
