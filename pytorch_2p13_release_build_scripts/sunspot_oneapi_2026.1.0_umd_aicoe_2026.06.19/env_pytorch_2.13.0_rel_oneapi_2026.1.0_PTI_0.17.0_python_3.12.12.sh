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
CONDA_ENV_INSTALL_DIR=/lus/tegu/projects/datasets/software/26.181.0/wheelforge/envs/conda_envs
CONDA_ENV_NAME=env_pytorch_2.13.0_rel_oneapi_2026.1.0_pti_0.17.0_numpy_2.5.1_python_3.12.12

WHEELHOUSE_TMP=/lus/tegu/projects/datasets/software/26.181.0/wheelhouse
WHEELHOUSE_DOWNLOAD=/lus/tegu/projects/datasets/software/26.181.0/wheelforge/downloaded_wheels
PYTORCH_REPO_DIR=/lus/tegu/projects/datasets/software/26.181.0/wheelforge/repositories/pytorch_2.13.0_07_21_2026/pytorch
TMPDIR_FOR_ENVS=/lus/tegu/projects/datasets/software/26.181.0/wheelforge/envs/tmpdir_for_envs

module add miniforge3/25.11.0-1
source $MINIFORGE3_ROOT/bin/activate
# The line above does exactly the line below
#source /opt/aurora/26.181.0/spack/unified/1.1.1/install/linux-x86_64/miniforge3-25.11.0-1-khkcc6i/bin/activate

ENVPREFIX=$CONDA_ENV_INSTALL_DIR/$CONDA_ENV_NAME
CONDA_ENV_MANIFEST=${CONDA_ENV_INSTALL_DIR}/manifests/${CONDA_ENV_NAME}

rm -rf ${ENVPREFIX}
mkdir -p ${ENVPREFIX}

rm -rf ${CONDA_ENV_MANIFEST}
mkdir -p ${CONDA_ENV_MANIFEST}

export CONDA_PKGS_DIRS=${ENVPREFIX}/../.conda/pkgs
export PIP_CACHE_DIR=${ENVPREFIX}/../.pip

echo "Creating Conda environment with Python 3.12.12"
conda create python=3.12.12 glog gflags fmt --prefix ${ENVPREFIX} --override-channels \
           --channel conda-forge \
           --strict-channel-priority \
           --yes

conda activate ${ENVPREFIX}
echo "Conda is coming from $(which conda)"

# Use default modules on Aurora with oneapi/2026.1.0 with PTI 0.17.0
# Use umd_aicoe_2026.06.19
ml add intel_gpu_umd_aicoe/2026.06.19
module add cmake
unset CMAKE_ROOT
module add ninja
module add pti-gpu
module add hdf5

export CXX=$(which g++)
export CC=$(which gcc)
#export CXX=$(which icpx)
#export CC=$(which icx)

export CFLAGS="-Wno-error=free-nonheap-object"

export REL_WITH_DEB_INFO=1
export USE_CUDA=0
export USE_ROCM=0
export USE_MKLDNN=1
export USE_MKL=1
export USE_ROCM=0
export USE_CUDNN=0
export USE_FBGEMM=0
export USE_NNPACK=0
export USE_QNNPACK=0
export USE_NCCL=0
export USE_CUDA=0
export BUILD_CAFFE2_OPS=0
export BUILD_TEST=0
export USE_DISTRIBUTED=1
export USE_NUMA=0
export USE_MPI=0
export _GLIBCXX_USE_CXX11_ABI=1
export USE_XPU=1
export USE_XCCL=1
export XPU_ENABLE_KINETO=1
export USE_ONEMKL=1
export USE_KINETO=1

export USE_AOT_DEVLIST='pvc'
export TORCH_XPU_ARCH_LIST='pvc'

export INTEL_MKL_DIR=$MKLROOT

## CHANGE HERE!!!
TMP_WORK=${TMPDIR_FOR_ENVS}
cd $TMP_WORK

mkdir -p ${CONDA_ENV_NAME}

LOG_FILE=${TMP_WORK}/${CONDA_ENV_NAME}/module-$(tstamp).log

touch ${LOG_FILE}
module -t list 2>&1 | tee ${LOG_FILE}

#git clone https://github.com/pytorch/pytorch.git
#cd pytorch
#git checkout v2.13.0
#git submodule sync && git submodule update --init --recursive

pip install conda-pack ipython uv
pip install --no-cache-dir -r ${WHEELHOUSE_TMP}/torch_2.13.0_triton_xpu_3.7.2_combined_requirements.txt

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
        "mkl-include"
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
        "mkl-static"
        "libgcc"
        "libgcc-ng"
        "libgomp"
        "liblzma"
        "libnsl"
        "libstdcxx"
        "libstdcxx-ng"
        "libuuid"
        "libxcrypt"
        "ncurses"
        "ld_impl_linux-64"
        "icu"
    )

for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

pip uninstall -y numpy
pip install --no-cache-dir numpy==2.2.6

#make triton
# The following is the correct version of triton-xpu
# https://github.com/pytorch/pytorch/blob/v2.13.0/.ci/docker/triton_xpu_version.txt
# pip install --no-cache-dir triton-xpu==3.7.2 --index-url https://download.pytorch.org/whl/
# Using triton from the downloaded wheels for  the first iteration. 
# We will try to build from source, if this does not work satisfactorily

pip install --no-deps --no-cache-dir --force-reinstall ${WHEELHOUSE_DOWNLOAD}/triton_xpu-*.whl 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"triton-xpu-install-whl-$(tstamp).log"
pip install --no-deps --no-cache-dir --force-reinstall ${WHEELHOUSE_TMP}/torch-*.whl 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"torch-install-$(tstamp).log"

echo "Finished installing the pytorch/2.13.0 wheel with numpy/2.2.6 and dependencies"

echo ""
echo "Writing the package lists"
conda list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_conda_env.list 2>&1
pip list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_pip.list 2>&1
echo "Package list writing finished"

echo "Writing $CONDA_ENV_MANIFEST/${CONA_ENV_NAME}_all.list"
cat $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_conda_env.list | grep -v '^#' | grep 'pypi$' | perl -pe 's/^(\S+)\s+(\S+).*/$1==$2/' >  $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_all.list

 
