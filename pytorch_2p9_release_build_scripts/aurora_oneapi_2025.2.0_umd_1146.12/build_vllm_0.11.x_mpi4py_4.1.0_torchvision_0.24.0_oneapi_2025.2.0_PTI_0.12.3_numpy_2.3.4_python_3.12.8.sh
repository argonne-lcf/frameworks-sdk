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
CONDA_ENV_NAME=vllm_0.11.x_mpi4py_4.1.0_torchvision_0.24.0_oneapi_2025.2.0_pti_0.12.3_numpy_2.3.4_python3.12.8

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
# Load hdf5 module, this loads hdf5/1.14.6
module restore
module load cmake
unset CMAKE_ROOT
module load pti-gpu
module load hdf5

TMP_WORK=/lus/flare/projects/datasets/softwares/envs/repositories/vllm_0.11.x+git6e97eccf5_11_06_2025
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
pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/torchvision-*.whl
pip install --no-deps --no-cache-dir --force-reinstall $LOCAL_WHEEL_LOC/mpi4py-*.whl

mkdir -p ${CONDA_ENV_NAME}

#git clone git@github.com:vllm-project/vllm.git
cd vllm/
#git checkout 6e97eccf5dd5036e26d63141d2bc1a9ea17a2cc8
# HEAD is now at 6e97eccf5 [XPU] Enable custom routing functions in IPEX for Llama4 (#28004)
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

pip install outlines_core==0.2.11 --no-deps
pip install --no-cache-dir -r ${LOCAL_WHEEL_LOC}/vllm_0.11.x_xpu_separate_requirements.txt

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
pip install --no-cache-dir pytorch-triton-xpu==3.5.0 --index-url https://download.pytorch.org/whl/

## Final round of cleanup
for pkg in "${rm_conda_pkgs[@]}"
do
    conda uninstall $pkg \
        --prefix ${ENVPREFIX} \
        --force \
        --yes
    pip uninstall $pkg -y
done

python setup.py clean --all
VLLM_TARGET_DEVICE=xpu python setup.py bdist_wheel --dist-dir ${TMP_WORK}/${CONDA_ENV_NAME} 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"vllm-build-whl-$(tstamp).log"

echo ""
echo "Completed build vllm/0.11.x wheel with mpi4py/4.1.0 and oneapi/2025.2.0 with numpy/2.3.4 for PyTorch-2.9.1 with IPEX-2.9.10" 
echo ""

VLLM_WHEEL_LOC=${TMP_WORK}/${CONDA_ENV_NAME}
pip install --no-deps --no-cache-dir --force-reinstall $VLLM_WHEEL_LOC/vllm-*.whl 2>&1 | tee ${TMP_WORK}/${CONDA_ENV_NAME}/"vllm-install-$(tstamp).log"
echo ""
echo "Finished installing the vllm/0.11.x wheel and dependencies"
echo ""

echo ""
echo "Writing the package lists"
conda list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_conda_env.list 2>&1
pip list > $CONDA_ENV_MANIFEST/${CONDA_ENV_NAME}_pip.list 2>&1
echo "Package list writing finished"
