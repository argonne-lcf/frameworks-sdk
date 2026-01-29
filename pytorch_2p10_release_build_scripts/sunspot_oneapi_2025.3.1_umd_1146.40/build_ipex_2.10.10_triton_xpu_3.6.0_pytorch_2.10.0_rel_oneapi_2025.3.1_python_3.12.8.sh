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
CONDA_ENV_INSTALL_DIR=/lus/tegu/projects/datasets/software/26.26.0/wheelforge/envs/conda_envs
CONDA_ENV_NAME=ipex_2.10.10_triton_xpu_3.6.0_pytorch_2.10.0_rel_oneapi_2025.3.1_numpy_2.2.6_python_3.12.8

WHEELHOUSE_TMP=/lus/tegu/projects/datasets/software/26.26.0/wheelhouse
PYTORCH_REPO_DIR=/lus/tegu/projects/datasets/software/26.26.0/wheelforge/repositories/pytorch_2.10.0_01_27_2026/pytorch

module add miniforge3/25.3.0-3
source $MINIFORGE3_ROOT/bin/activate
# The line above does exactly the line below
#source /opt/aurora/26.26.0/spack/unified/1.1.1/install/linux-x86_64/miniforge3-25.3.0-3-w5hoacg/bin/activate

ENVPREFIX=$CONDA_ENV_INSTALL_DIR/$CONDA_ENV_NAME
CONDA_ENV_MANIFEST=${CONDA_ENV_INSTALL_DIR}/manifests/${CONDA_ENV_NAME}

rm -rf ${ENVPREFIX}
mkdir -p ${ENVPREFIX}

rm -rf ${CONDA_ENV_MANIFEST}
mkdir -p ${CONDA_ENV_MANIFEST}

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

# Use default modules on Aurora with oneapi/2025.3.1 with PTI 0.16.0-rc1
module add cmake
unset CMAKE_ROOT
module add ninja
module add pti-gpu
module add hdf5

TMP_WORK=/lus/tegu/projects/datasets/software/26.26.0/wheelforge/repositories/ipex_2.10.10_01_28_2026
cd $TMP_WORK

mkdir -p ${CONDA_ENV_NAME}

LOG_FILE=${TMP_WORK}/${CONDA_ENV_NAME}/module-$(tstamp).log

touch ${LOG_FILE}
module -t list 2>&1 | tee ${LOG_FILE}

#git clone git@github.com:intel/intel-extension-for-pytorch.git
cd intel-extension-for-pytorch
#git checkout v2.10.10+xpu
#git submodule sync && git submodule update --init --recursive

# Installing a couple of portability tools
pip install conda-pack ipython 

## installing ipex, pytorch and triton-xpu requirements
pip install --no-cache-dir -r ${WHEELHOUSE_TMP}/ipex_2.10.10_triton_xpu_3.6.0_pytorch_2.10.0_combined_requirements.txt

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
pip install --no-cache-dir numpy==2.2.6

## Install PyTorch 2.10.0a0+git449b176 wheel
## Install triton-xpu 3.6.0+git225cdbde wheel
pip install --no-deps --no-cache-dir --force-reinstall $WHEELHOUSE_TMP/torch-*.whl
pip install --no-deps --no-cache-dir --force-reinstall $WHEELHOUSE_TMP/triton-*.whl

export DPCPP_ROOT=$(realpath $(dirname $(which icpx))/..)
export CXX=$(which g++)
export CC=$(which gcc)

#export REL_WITH_DEB_INFO=1
export BUILD_DOUBLE_KERNEL=ON
export MKL_DPCPP_ROOT=${MKLROOT}
#export INTEL_MKL_DIR=$MKLROOT
export USE_ITT_ANNOTATION=ON
export BUILD_WITH_CPU=ON
export _GLIBCXX_USE_CXX11_ABI=1
export TORCH_DEVICE_BACKEND_AUTOLOAD=0
export USE_AOT_DEVLIST="pvc"
export TORCH_XPU_ARCH_LIST="pvc"
export USE_CUTLASS_KERNELS=1

export CXXFLAGS="$CXXFLAGS -Wno-all -w"
export CFLAGS="$CFLAGS -Wno-all -w"

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

python setup.py clean --all

MAX_JOBS=16 python setup.py bdist_wheel --dist-dir ${TMP_WORK}/${CONDA_ENV_NAME} 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"ipex-build-whl-$(tstamp).log"
echo "Finished building ipex/2.10.10+xpu triton_xpu_3.6.0 for PyTorch 2.9.1 wheel with numpy 2.2.6 with oneapi/2025.3.1"

## This is a safety check. It seems the wheel building process brings in 
## mkl and mkl-include
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


LOCAL_WHEEL_LOC=${TMP_WORK}/${CONDA_ENV_NAME}
pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/intel_extension_for_pytorch-*.whl 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"ipex-install-$(tstamp).log"
echo "Finished installing the wheel and dependencies"

echo ""
echo "Writing the package lists"
echo "Writing $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_conda_env.list"
conda list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_conda_env.list 2>&1
echo "Writing $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_pip.list" 
pip list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_pip.list 2>&1
echo "Package list writing finished"

echo "Writing $CONDA_ENV_MANIFEST/${CONA_ENV_NAME}_all.list"
cat $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_conda_env.list | grep -v '^#' | grep 'pypi$' | perl -pe 's/^(\S+)\s+(\S+).*/$1==$2/' >  $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_all.list

 
