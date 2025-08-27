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
CONDA_ENV_INSTALL_DIR=/lus/tegu/projects/datasets/software/wheelforge/envs/conda_envs
CONDA_ENV_NAME=py3p10p18_vllm_0.10.1_pytorch_2.8.0_nre_oneapi_2025.2.0_numpy_2.0.2_python3p10p18

source /opt/aurora/25.190.0/spack/unified/0.10.0/install/linux-sles15-x86_64/gcc-13.3.0/miniforge3-24.3.0-0-gfganax/bin/activate

ENVPREFIX=$CONDA_ENV_INSTALL_DIR/$CONDA_ENV_NAME
CONDA_ENV_MANIFEST=${CONDA_ENV_INSTALL_DIR}/manifests/${CONDA_ENV_NAME}

rm -rf ${CONDA_ENV_MANIFEST}
mkdir -p ${CONDA_ENV_MANIFEST}
 
rm -rf ${ENVPREFIX}
mkdir -p ${ENVPREFIX}

export CONDA_PKGS_DIRS=${ENVPREFIX}/../.conda/pkgs
export PIP_CACHE_DIR=${ENVPREFIX}/../.pip

echo "Creating Conda environment with Python 3.10.18"
conda create python=3.10.18 --prefix ${ENVPREFIX} --override-channels \
           --channel conda-forge \
           --strict-channel-priority \
           --yes

conda activate ${ENVPREFIX}

echo "Conda is coming from $(which conda)"

# Load default modules with oneapi/2025.2.0 with PTI 0.12.3 on Sunspot
# Load hdf5 module, this loads hdf5/1.14.6
module restore
module load cmake
unset CMAKE_ROOT
module load pti-gpu
module load hdf5

## Scikit-learn specific
export MPIROOT=$MPI_ROOT

TMP_WORK=/lus/tegu/projects/datasets/software/wheelforge/repositories/envs/conda_envs
cd $TMP_WORK

LOCAL_WHEEL_LOC=/lus/tegu/projects/datasets/software/wheelhouse

pip install --no-cache-dir -r ${LOCAL_WHEEL_LOC}/torchdata_0.11.0_torchao_0.12.0_h5py_3.14.0_torchvision_0.23.0_ipex_2.8.10_pytorch_2.8.0_triton_xpu_3.4.0_combined_requirements.txt
pip install --no-cache-dir -r ${LOCAL_WHEEL_LOC}/legacy_nre_requirements.txt

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
        "nvidia-nccl-cu12"
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
pip install --no-cache-dir numpy==2.0.2
pip install --no-cache-dir pytorch-triton-xpu==3.4.0 --index-url https://download.pytorch.org/whl/nightly/

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
pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/torchvision-*.whl
pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/mpi4py-*.whl
pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/h5py-*.whl
pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/torchdata-*.whl


mkdir -p ${CONDA_ENV_NAME}

#git clone git@github.com:IntelPython/numba-dpex.git
#cd numba-dpex/
#git checkout 0.23.0
#git submodule sync && git submodule update --init --recursive
# Make changes to numba_dpex/__init__.py L44 replace *DPCTLSyclInterface.so  with *libDPCTLSyclInterface.so

export CXX=$(which g++)
export CC=$(which gcc)
echo "CXX = $CXX"
echo "CC = $CC"

export REL_WITH_DEB_INFO=1
export USE_CUDA=0
export USE_XPU=1
export USE_XCCL=1

pip uninstall -y mkl mkl-include
pip install --no-cache-dir -r ${LOCAL_WHEEL_LOC}/torchao_0.12.0_xpu_separate_requirements.txt
pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/torchao-*.whl

for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

pip install --no-cache-dir -r ${LOCAL_WHEEL_LOC}/torchtune_0.6.1_xpu_separate_requirements.txt

for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/torchtune-*.whl

pip install outlines_core==0.2.10 --no-deps
pip install --no-cache-dir -r ${LOCAL_WHEEL_LOC}/vllm_0.10.1_xpu_separate_requirements.txt

for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

## vllm's complex inter-dependency sometimes brings own triton, triton-xpu
pip uninstall -y triton pytorch-triton pytorch-triton-xpu

## installing back our preferred version
pip install --no-cache-dir pytorch-triton-xpu==3.4.0 --index-url https://download.pytorch.org/whl/nightly/

for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/vllm-*.whl

pip install --no-cache-dir -r ${LOCAL_WHEEL_LOC}/deepspeed_0.17.5_xpu_specific_requirements.txt

for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

pip uninstall nvidia-nccl-cu12 -y

pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/deepspeed-*.whl
pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/scikit_learn_intelex-*.whl

pip install --no-cache-dir -r ${LOCAL_WHEEL_LOC}/dpctl_0.20.0_xpu_requirements.txt

for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/dpctl-*.whl
pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/dpnp-*.whl
## This is a wheel built from Intel-dpcpp-llvm-spirv archived package, dependecy of numba-dpex/0.23.0
## This package does not have any dependency other than Python >= 3.10
## https://github.com/IntelPython/dpcpp-llvm-spirv/tree/main
## Modified to match Aurora compute image. Courtesy: Christopher Chan-Nui
## We will source, maintain and version control this modified package
pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/aurora_dpcpp_llvm_spirv-*.whl
pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/numba_dpex-*.whl

echo ""
echo "Finished installing the environment to test vllm/0.10.1 with Python 3.10.18"
echo ""

echo ""
echo "Writing the package lists"
conda list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_conda_env.list 2>&1
pip list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_pip.list 2>&1
echo "Package list writing finished"
