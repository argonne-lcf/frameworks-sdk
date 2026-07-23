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
CONDA_ENV_NAME=vllm_xpu_kernels_0.1.10.1_vllm_0.25.1_nre_pt_2.13.0_rel_one_2026.1.0_np_2.3.5_python_3.12.12

WHEELHOUSE_TMP=/lus/tegu/projects/datasets/software/26.181.0/wheelhouse
WHEELHOUSE_DOWNLOAD=/lus/tegu/projects/datasets/software/26.181.0/wheelforge/downloaded_wheels
PYTORCH_REPO_DIR=/lus/tegu/projects/datasets/software/26.181.0/wheelforge/repositories/pytorch_2.13.0_07_21_2026/pytorch
TMPDIR_FOR_ENVS=/lus/tegu/projects/datasets/software/26.181.0/wheelforge/envs/tmpdir_for_envs

VLLM_XPU_KERNELS_REPO_DIR=/lus/tegu/projects/datasets/software/26.181.0/wheelforge/repositories/vllm_xpu_kernels_0.1.10.1_07_22_2026
VLLM_REPO_DIR=/lus/tegu/projects/datasets/software/26.181.0/wheelforge/repositories/vllm_0.25.1_07_22_2026

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
TMP_WORK=/lus/tegu/projects/datasets/software/26.181.0/wheelforge/repositories/vllm_xpu_kernels_0.1.10.1_07_22_2026
cd $TMP_WORK

mkdir -p ${CONDA_ENV_NAME}

LOG_FILE=${TMP_WORK}/${CONDA_ENV_NAME}/module-$(tstamp).log

touch ${LOG_FILE}
module -t list 2>&1 | tee ${LOG_FILE}

#git clone https://github.com/vllm-project/vllm-xpu-kernels.git
cd vllm-xpu-kernels
#git checkout v0.1.10.1
#git submodule sync && git submodule update --init --recursive

## Apply vllm-xpu-kernels patch

python <<'EOF'
import pathlib, re
f = pathlib.Path("csrc/utils/mem_info.cpp")
src = f.read_text()
new = re.sub(
    r"size_t getUsableMemory\(ze_device_handle_t& device\) \{.*?\n\}",
    (
        "size_t getUsableMemory(ze_device_handle_t& device) {\n"
        "  // Local build patch: driver L0 headers predate USABLEMEM_SIZE_EXT.\n"
        "  // Fall back to reporting total memory as \"usable\"; downstream KV-cache\n"
        "  // sizing treats a slightly over-optimistic value safely on dedicated GPUs.\n"
        "  return getTotalMemory(device);\n"
        "}"
    ),
    src, count=1, flags=re.DOTALL,
)
assert new != src, "patch didn't apply — check csrc/utils/mem_info.cpp"
f.write_text(new)
print("patched:", f)
EOF

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

export VLLM_TARGET_DEVICE=xpu
export VLLM_XPU_AOT_DEVICES="pvc"
export VLLM_XPU_XE2_AOT_DEVICES="pvc"
export VLLM_WORKER_MULTIPROC_METHOD=spawn

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
pip install --no-deps --no-cache-dir --force-reinstall ${WHEELHOUSE_TMP}/torchdata-*.whl

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

pip install outlines_core==0.2.14 --no-deps
pip install compressed-tensors==0.17.0 --no-deps
pip install --no-deps "xgrammar>=0.2.1,<1.0.0"
pip install --no-deps "auto_round_lib>=0.14.0"
pip install --no-cache-dir -r ${WHEELHOUSE_TMP}/vllm_0.25.1_xpu_separate_requirements.txt

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

## vllm's complex inter-dependency sometimes brings own triton, triton-xpu
pip uninstall -y triton pytorch-triton pytorch-triton-xpu
pip install --no-deps --no-cache-dir --force-reinstall ${WHEELHOUSE_DOWNLOAD}/triton_xpu-*.whl

VLLM_XPU_KERNELS_LOCAL_WHEEL_LOC=${VLLM_XPU_KERNELS_REPO_DIR}/${CONDA_ENV_NAME}
VLLM_LOCAL_WHEEL_LOC=${VLLM_REPO_DIR}/${CONDA_ENV_NAME}

mkdir -p ${VLLM_XPU_KERNELS_LOCAL_WHEEL_LOC}
mkdir -p ${VLLM_LOCAL_WHEEL_LOC}

echo "Removing vllm-xpu-kernels previous build artifacts"
rm -rf ${VLLM_XPU_KERNELS_REPO_DIR}/vllm-xpu-kernels/build
rm -rf ${VLLM_XPU_KERNELS_REPO_DIR}/vllm-xpu-kernels/dist
rm -rf ${VLLM_XPU_KERNELS_REPO_DIR}/vllm-xpu-kernels/*.egg-info
echo "Removing done"

echo "Starting vllm-xpu-kernels build process"
VLLM_TARGET_DEVICE="xpu" \
    VLLM_XPU_AOT_DEVICES="pvc" \
    VLLM_XPU_XE2_AOT_DEVICES="pvc" \
    python -m pip wheel --verbose --no-deps --no-build-isolation \
    ${VLLM_XPU_KERNELS_REPO_DIR}/vllm-xpu-kernels --wheel-dir ${VLLM_XPU_KERNELS_LOCAL_WHEEL_LOC} \
    2>&1 | tee ${VLLM_XPU_KERNELS_LOCAL_WHEEL_LOC}/"vllm-xpu-kernels-build-whl-$(tstamp).log"
echo "Finished building vllm-xpu-kernels/0.1.10.1, triton_xpu_3.7.2 for PyTorch 2.13.0 wheel with numpy 2.3.5 with oneapi/2026.1.0"

pip install --no-deps --no-cache-dir --force-reinstall ${VLLM_XPU_KERNELS_LOCAL_WHEEL_LOC}/vllm_xpu_kernels-*.whl 2>&1 | tee ${VLLM_XPU_KERNELS_LOCAL_WHEEL_LOC}/"vllm-xpu-kernels-install-$(tstamp).log"
echo "Finished installing the vllm-xpu-kernels/0.1.10.1 wheel with numpy/2.3.5 and dependencies"

echo "Removing vllm previous build artifacts"
rm -rf ${VLLM_REPO_DIR}/vllm/build
rm -rf ${VLLM_REPO_DIR}/vllm/dist
rm -rf ${VLLM_REPO_DIR}/vllm/*.egg-info
echo "Removing done"

echo "Starting vllm build process"
CMAKE_ARGS="-DCMAKE_CXX_COMPILER=$(which g++) -DCMAKE_C_COMPILER=$(which gcc)" \
    CXX=$(which g++) CC=$(which gcc) VLLM_TARGET_DEVICE=xpu \
    VLLM_WORKER_MULTIPROC_METHOD=spawn \
    python -m pip wheel --verbose --no-deps --no-build-isolation \
    ${VLLM_REPO_DIR}/vllm --wheel-dir ${VLLM_LOCAL_WHEEL_LOC} \
    2>&1 | tee ${VLLM_LOCAL_WHEEL_LOC}/"vllm-build-whl-$(tstamp).log" 
echo "Finished building vllm/0.25.1, triton_xpu_3.7.2 for PyTorch 2.13.0 wheel with numpy 2.3.5 with oneapi/2026.1.0"

pip install --no-deps --no-cache-dir --force-reinstall ${VLLM_LOCAL_WHEEL_LOC}/vllm-*.whl 2>&1 | tee ${VLLM_LOCAL_WHEEL_LOC}/"vllm-install-$(tstamp).log"
echo "Finished installing the vllm/0.25.1 wheel with numpy/2.3.5 and dependencies"

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

 
