#!/bin/bash

if [ ! -d vllm-xpu-kernels ]; then
  git clone --depth 1 https://github.com/vllm-project/vllm-xpu-kernels.git vllm-xpu-kernels
else
  echo "Skipping clone: vllm-xpu-kernels already exists"
fi

if [ ! -d cutlass-sycl-src ]; then
  mkdir -p cutlass-sycl-src
  curl -L https://github.com/intel/sycl-tla/archive/refs/heads/main.tar.gz | \
    tar -xz --strip-components=1 -C cutlass-sycl-src \
      sycl-tla-main/include sycl-tla-main/tools/util/include
else
  echo "Skipping download: cutlass-sycl-src already exists"
fi

export CUTLASS_SRC="${VLLM_CUTLASS_SRC_DIR:-$PWD/cutlass-sycl-src}"

icpx -std=c++17 -O3 -DNDEBUG -Werror -fsycl \
  -fsycl-targets=spir64_gen   -Xsycl-target-backend "-device pvc" \
  -I${CUTLASS_SRC}/include \
  -I${CUTLASS_SRC}/tools/util/include \
  -DCUTLASS_ENABLE_HEADERS_ONLY \
  -DCUTLASS_ENABLE_SYCL \
  -DSYCL_INTEL_TARGET \
  -DCUTLASS_VERSIONS_GENERATED \
  repro_xe2_store_sycl.cpp \
  -o repro_xe2_store_sycl
