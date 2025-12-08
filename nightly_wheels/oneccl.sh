#!/bin/sh

# 4) Build oneCCL bindings
git clone https://github.com/intel/torch-ccl
cd torch-ccl
#FIXME need to checkout c27ded5 or create a patch because the repo version.txt is messed up
git checkout c27ded5
git submodule sync && git submodule update --init --recursive
#pip install -r requirements.txt
ONECCL_BINDINGS_FOR_PYTORCH_BACKEND=xpu \
    INTELONEAPIROOT="$ONEAPI_ROOT" USE_SYSTEM_ONECCL=ON COMPUTE_BACKEND=dpcpp \
    python setup.py bdist_wheel \
    > "ccl-build-whl-$(date +%Y-%m-%d-%H%M%S).log" 2>&1
pip install dist/*.whl
cd ../
