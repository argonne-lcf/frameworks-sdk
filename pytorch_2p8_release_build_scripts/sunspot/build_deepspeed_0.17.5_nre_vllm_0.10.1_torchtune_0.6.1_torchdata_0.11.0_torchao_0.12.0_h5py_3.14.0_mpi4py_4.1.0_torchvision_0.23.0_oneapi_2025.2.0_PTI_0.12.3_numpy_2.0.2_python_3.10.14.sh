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
CONDA_ENV_NAME=deepspeed_0.17.5_nre_vllm_0.10.1_torchtune_0.6.1_torchdata_0.11.0_torchao_0.12.0_h5py_3.14.0_mpi4py_4.1.0_torchvision_0.23.0_oneapi_2025.2.0_pti_0.12.3_numpy_2.0.2_python3p10p14_RC2

source /opt/aurora/25.190.0/spack/unified/0.10.0/install/linux-sles15-x86_64/gcc-13.3.0/miniforge3-24.3.0-0-gfganax/bin/activate

ENVPREFIX=$CONDA_ENV_INSTALL_DIR/$CONDA_ENV_NAME
CONDA_ENV_MANIFEST=${CONDA_ENV_INSTALL_DIR}/manifests/${CONDA_ENV_NAME}

rm -rf ${CONDA_ENV_MANIFEST}
mkdir -p ${CONDA_ENV_MANIFEST}
 
rm -rf ${ENVPREFIX}
mkdir -p ${ENVPREFIX}

export CONDA_PKGS_DIRS=${ENVPREFIX}/../.conda/pkgs
export PIP_CACHE_DIR=${ENVPREFIX}/../.pip

echo "Creating Conda environment with Python 3.10.14"
conda create python=3.10.14 --prefix ${ENVPREFIX} --override-channels \
           --channel https://software.repos.intel.com/python/conda/linux-64 \
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

TMP_WORK=/lus/tegu/projects/datasets/software/wheelforge/repositories/deepspeed_0.17.5_rel_08_21_2025
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

#git clone git@github.com:deepspeedai/DeepSpeed.git
cd DeepSpeed/
#git checkout v0.17.5
#git submodule sync && git submodule update --init --recursive

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

python setup.py clean --all
python setup.py bdist_wheel --dist-dir ${TMP_WORK}/${CONDA_ENV_NAME} 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"deepspeed-build-whl-$(tstamp).log"

echo ""
echo "Completed build deepspeed/0.17.5 wheel with mpi4py/4.1.0 and oneapi/2025.2.0 with numpy/2.0.2 for PyTorch-2.8.0 with IPEX-2.8.10" 
echo ""

DEEPSPEED_WHEEL_LOC=${TMP_WORK}/${CONDA_ENV_NAME}
pip install --no-deps --no-cache-dir --force-reinstall $DEEPSPEED_WHEEL_LOC/deepspeed-*.whl 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"deepspeed-install-$(tstamp).log"
echo ""
echo "Finished installing the deepspeed/0.17.5 wheel and dependencies"
echo ""

echo ""
echo "Writing the package lists"
conda list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_conda_env.list 2>&1
pip list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_pip.list 2>&1
echo "Package list writing finished"
