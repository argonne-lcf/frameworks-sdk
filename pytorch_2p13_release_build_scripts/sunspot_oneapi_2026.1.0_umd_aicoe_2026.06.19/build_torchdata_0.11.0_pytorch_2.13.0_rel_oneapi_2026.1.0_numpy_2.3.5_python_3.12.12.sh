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
CONDA_ENV_NAME=torchdata_0.11.0_nre_pt_2.13.0_rel_one_2026.1.0_np_2.3.5_python_3.12.12

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

## CHANGE HERE!!!
TMP_WORK=/lus/tegu/projects/datasets/software/26.181.0/wheelforge/repositories/torchdata_0.11.0_07_22_2026
cd $TMP_WORK

mkdir -p ${CONDA_ENV_NAME}

LOG_FILE=${TMP_WORK}/${CONDA_ENV_NAME}/module-$(tstamp).log

touch ${LOG_FILE}
module -t list 2>&1 | tee ${LOG_FILE}

#git clone https://github.com/meta-pytorch/data.git
cd data
#git checkout v0.11.0
#git submodule sync && git submodule update --init --recursive

pip install conda-pack ipython uv
pip install --no-cache-dir -r ${WHEELHOUSE_TMP}/h5py_3.16.0_torchvision_0.28.0_torch_2.13.0_triton_xpu_3.7.2_combined_requirements.txt
pip install --no-cache-dir -r ${WHEELHOUSE_TMP}/legacy_nre_requirements.txt

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

pip uninstall -y numpy numpy-base
pip install --no-cache-dir numpy==2.3.5

pip install --no-deps --no-cache-dir --force-reinstall ${WHEELHOUSE_DOWNLOAD}/triton_xpu-*.whl
pip install --no-deps --no-cache-dir --force-reinstall ${WHEELHOUSE_TMP}/torch-*.whl 
pip install --no-deps --no-cache-dir --force-reinstall ${WHEELHOUSE_TMP}/torchvision-*.whl
pip install --no-deps --no-cache-dir --force-reinstall ${WHEELHOUSE_TMP}/mpi4py-*.whl
pip install --no-deps --no-cache-dir --force-reinstall ${WHEELHOUSE_TMP}/h5py-*.whl

export CXX=$(which g++)
export CC=$(which gcc)

export _GLIBCXX_USE_CXX11_ABI=1
export REL_WITH_DEB_INFO=1
export USE_CUDA=0
export USE_XPU=1
export USE_XCCL=1

pip install --no-cache-dir -r ${WHEELHOUSE_TMP}/torchao_0.17.0_xpu_separate_requirements.txt
## Special to resolve requirement for spin==0.18
pip install --no-cache-dir click==8.3.3 

for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

pip uninstall -y numpy numpy-base
pip install --no-cache-dir numpy==2.3.5

pip install --no-deps --no-cache-dir --force-reinstall ${WHEELHOUSE_TMP}/torchao-*.whl

python setup.py clean --all

python setup.py bdist_wheel --dist-dir ${TMP_WORK}/${CONDA_ENV_NAME} 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"torchdata-build-whl-$(tstamp).log"
echo "Finished building torchdata/0.11.0, triton_xpu_3.7.2 for PyTorch 2.13.0 wheel with numpy 2.3.5 with oneapi/2026.1.0"

LOCAL_WHEEL_LOC=${TMP_WORK}/${CONDA_ENV_NAME}
pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/torchdata-*.whl 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"torchdata-install-$(tstamp).log"
echo "Finished installing the torchdata/0.11.0 wheel with numpy/2.3.5 and dependencies"

echo "Doing a final clean up"

for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

pip uninstall -y numpy numpy-base
pip install --no-cache-dir numpy==2.3.5

echo ""
echo "Writing the package lists"
conda list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_conda_env.list 2>&1
pip list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_pip.list 2>&1
echo "Package list writing finished"

echo "Writing $CONDA_ENV_MANIFEST/${CONA_ENV_NAME}_all.list"
cat $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_conda_env.list | grep -v '^#' | grep 'pypi$' | perl -pe 's/^(\S+)\s+(\S+).*/$1==$2/' >  $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_all.list

 
