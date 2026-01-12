#!/bin/sh

set -xe
source ../ci-lib.sh

# 0) Get pytorch wheel as argument
while getopts 't:' opt; do
    case "$opt" in
        t)
            TORCH_WHEEL="$(realpath $OPTARG)";;
    esac
done

if [ -z "$TORCH_WHEEL" ]; then
    echo "Usage: $0 -t <pytorch_wheel>" 1>&2
    exit 1
fi

# 1) Pull source and gen build environment
gen_build_dir_with_git 'https://github.com/intel/intel-extension-for-pytorch' -b xpu-main
setup_build_env
pushd 'intel-extension-for-pytorch'

uv venv --python 3.12
uv pip install --no-cache --link-mode=copy -r requirements.txt pip "$TORCH_WHEEL"

# 2) Set IPEX build configuration
export CC="$(which gcc)"
export CXX="$(which g++)"
export INTELONEAPIROOT="$ONEAPI_ROOT"
export MAX_JOBS=16

# 3) Build Intel Extension for PyTorch
# build_bdist_wheel 'intel-extension-for-pytorch'
source .venv/bin/activate
python setup.py bdist_wheel
deactivate
popd

# 4) Cleanup
archive_artifacts 'intel-extension-for-pytorch'
cleanup_build_dir
