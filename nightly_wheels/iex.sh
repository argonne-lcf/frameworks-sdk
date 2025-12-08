#!/bin/sh

# 3) Build Intel Extension for PyTorch
git clone https://github.com/intel/intel-extension-for-pytorch
cd intel-extension-for-pytorch
git checkout xpu-main
git submodule sync && git submodule update --init --recursive
#pip install -r requirements.txt
MAX_JOBS=16 INTELONEAPIROOT="$ONEAPI_ROOT" \
    CC="$(which gcc)" CXX="$(which g++)" \
    python setup.py bdist_wheel \
    > "ipex-build-whl-$(date +%Y-%m-%d-%H%M%S).log" 2>&1
pip install dist/*.whl
cd ../
