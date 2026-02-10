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
CONDA_ENV_NAME=env_dpnp_0.19.1_scikit_2025.10.1_pytorch_2.10.0_rel_oneapi_2025.3.1_numpy_2.2.6_python_3.12.12

WHEELHOUSE_TMP=/lus/tegu/projects/datasets/software/26.26.0/wheelhouse
WHEELHOUSE_DOWNLOAD=/lus/tegu/projects/datasets/software/26.26.0/wheelforge/downloaded_wheels
PYTORCH_REPO_DIR=/lus/tegu/projects/datasets/software/26.26.0/wheelforge/repositories/pytorch_2.10.0_01_27_2026/pytorch

#module add miniforge3/25.3.0-3
#source $MINIFORGE3_ROOT/bin/activate
# The line above does exactly the line below
#source /opt/aurora/26.26.0/spack/unified/1.1.1/install/linux-x86_64/miniforge3-25.3.0-3-w5hoacg/bin/activate
source /opt/aurora/26.26.0/spack/unified/1.1.1/install/linux-x86_64/miniforge3-25.11.0-1-uydwzvt/bin/activate

ENVPREFIX=$CONDA_ENV_INSTALL_DIR/$CONDA_ENV_NAME
CONDA_ENV_MANIFEST=${CONDA_ENV_INSTALL_DIR}/manifests/${CONDA_ENV_NAME}

rm -rf ${ENVPREFIX}
mkdir -p ${ENVPREFIX}

rm -rf ${CONDA_ENV_MANIFEST}
mkdir -p ${CONDA_ENV_MANIFEST}

export CONDA_PKGS_DIRS=${ENVPREFIX}/../.conda/pkgs
export PIP_CACHE_DIR=${ENVPREFIX}/../.pip

echo "Creating Conda environment with Python 3.12.12"
conda create python=3.12.12 icu=73 glog gflags fmt \
    --prefix ${ENVPREFIX} --override-channels \
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
        "libstdcxx-ng"
        "libuuid"
        "libxcrypt"
        "ncurses"
        "ld_impl_linux-64"
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

#TMP_WORK=/lus/tegu/projects/datasets/software/26.26.0/wheelforge/repositories/dpnp_0.19.1_02_09_2026
TMP_WORK=/lus/tegu/projects/datasets/software/26.26.0/wheelforge/envs/tmpdir_for_envs
cd $TMP_WORK

mkdir -p ${CONDA_ENV_NAME}

LOG_FILE=${TMP_WORK}/${CONDA_ENV_NAME}/module-$(tstamp).log

touch ${LOG_FILE}
module -t list 2>&1 | tee ${LOG_FILE}

#git clone git@github.com:IntelPython/dpnp.git
#cd dpnp
#git checkout 0.19.1
#git submodule sync && git submodule update --init --recursive

# Installing a couple of portability tools
pip install conda-pack ipython 

## installing ipex, pytorch and triton-xpu requirements
pip install --no-cache-dir -r ${WHEELHOUSE_TMP}/h5py_3.15.1_torchvision_0.25.0_ipex_2.10.10_pytorch_2.10.0_combined_requirements.txt
pip install --no-cache-dir -r ${WHEELHOUSE_TMP}/legacy_nre_requirements.txt

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
pip install --no-deps --no-cache-dir --force-reinstall $WHEELHOUSE_TMP/intel_extension_for_pytorch-*.whl
pip install --no-deps --no-cache-dir --force-reinstall $WHEELHOUSE_TMP/torchvision-*.whl
pip install --no-deps --no-cache-dir --force-reinstall $WHEELHOUSE_TMP/mpi4py-*.whl
pip install --no-deps --no-cache-dir --force-reinstall $WHEELHOUSE_TMP/h5py-*.whl


export CXX=$(which g++)
export CC=$(which gcc)

#export CMAKE_PREFIX_PATH="$CONDA_PREFIX"

export REL_WITH_DEB_INFO=1

export USE_CUDA=0
export USE_XPU=1
export USE_XCCL=1

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

pip install --no-cache-dir -r ${WHEELHOUSE_TMP}/torchao_0.15.0_xpu_separate_requirements.txt
pip install --no-deps --no-cache-dir --force-reinstall $WHEELHOUSE_TMP/torchao-*.whl
pip install --no-deps --no-cache-dir --force-reinstall $WHEELHOUSE_TMP/torchdata-*.whl

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
##
pip install outlines_core==0.2.11 --no-deps
pip install --no-cache-dir -r ${WHEELHOUSE_TMP}/vllm_0.15.0_xpu_separate_requirements.txt

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
## Installing vLLM wheel
pip install --no-deps --no-cache-dir --force-reinstall --no-build-isolation $WHEELHOUSE_TMP/vllm-0.15.0+xpu-py3-none-any.whl

## Installing torchcomms wheel
pip install --no-deps --no-cache-dir --force-reinstall --no-build-isolation $WHEELHOUSE_TMP/torchcomms-*.whl

## Install dpctl requirements
pip install --no-cache-dir -r ${WHEELHOUSE_TMP}/deepspeed_0.18.5_xpu_separate_requirements.txt
#pip install --no-cache-dir --no-deps accelerate

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

## Install deepspeed==0.18.5
pip install --no-deps --no-cache-dir --no-build-isolation deepspeed==0.18.5

## Scikit Specific
export MPIROOT=${MPI_ROOT}

## Install scikitlearnintelex wheel
pip install --no-deps --no-cache-dir --force-reinstall --no-build-isolation $WHEELHOUSE_TMP/scikit_learn_intelex-*.whl

## Install dpctl/0.21.1 and dpnp/0.19.1 requirements
pip install --no-cache-dir -r ${WHEELHOUSE_TMP}/dpnp_0.19.1_dpctl_0.21.1_xpu_separate_requirements.txt

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

## Install dpctl/0.21.1 wheel
pip install --no-deps --no-cache-dir --force-reinstall --no-build-isolation $WHEELHOUSE_TMP/dpctl-*.whl

## Install dpnp/0.19.1 wheel
pip install --no-deps --no-cache-dir --force-reinstall --no-build-isolation $WHEELHOUSE_TMP/dpnp-*.whl

#LOCAL_WHEEL_LOC=${TMP_WORK}/${CONDA_ENV_NAME}
#pip install --no-deps --no-cache-dir --no-build-isolation ${LOCAL_WHEEL_LOC}/dpnp-*.whl 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"dpnp-install-$(tstamp).log"
echo "Finished installing dpnp/0.19.1 the wheel and dependencies"

echo "Doing a final clean up"

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


echo ""
echo "Writing the package lists"
echo "Writing $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_conda_env.list"
conda list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_conda_env.list 2>&1
echo ""
echo "Writing $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_pip.list"
pip list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_pip.list 2>&1
echo "Package list writing finished"
echo ""
echo "Writing $CONDA_ENV_MANIFEST/${CONA_ENV_NAME}_all.list"
cat $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_conda_env.list | grep -v '^#' | grep 'pypi$' | perl -pe 's/^(\S+)\s+(\S+).*/$1==$2/' >  $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_all.list

 
