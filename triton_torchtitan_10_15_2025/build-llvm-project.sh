#!/usr/bin/env bash

#REPO_ROOT="$(git rev-parse --show-toplevel)"
#
#git clone git@github.com:llvm/llvm-project.git
#cd llvm-project/
#git checkout f6ded0be897e2878612dd903f7e8bb85448269e5
#git submodule sync && git submodule update --init --recursive
REPO_ROOT=/lus/flare/projects/datasets/softwares/envs/repositories/llvm_proj_gitf6ded0be_10_21_2025

LLVM_TARGETS=${LLVM_TARGETS:-Native}
LLVM_PROJECTS=${LLVM_PROJECTS:-mlir;llvm;lld}
LLVM_BUILD_TYPE=${LLVM_BUILD_TYPE:-RelWithDebInfo}
#LLVM_COMMIT_HASH=${LLVM_COMMIT_HASH:-$(cat "$REPO_ROOT/cmake/llvm-hash.txt")}
LLVM_PROJECT_PATH=${LLVM_PROJECT_PATH:-"$REPO_ROOT/llvm-project"}
LLVM_BUILD_PATH=${LLVM_BUILD_PATH:-"$LLVM_PROJECT_PATH/build"}
LLVM_INSTALL_PATH=${LLVM_INSTALL_PATH:-"$LLVM_PROJECT_PATH/install"}
LLVM_PROJECT_URL=${LLVM_PROJECT_URL:-"https://github.com/llvm/llvm-project"}

mkdir -p ${LLVM_BUILD_PATH}
mkdir -p ${LLVM_INSTALL_PATH}

module add cmake
unset CMAKE_ROOT

if [ -z "$CMAKE_ARGS" ]; then
    if [ "$#" -eq 0 ]; then
        CMAKE_ARGS=( 
            -G Ninja 
            -DCMAKE_BUILD_TYPE="$LLVM_BUILD_TYPE" 
            -DLLVM_CCACHE_BUILD=OFF
            -DLLVM_ENABLE_ASSERTIONS=ON
            -DCMAKE_C_COMPILER=/opt/aurora/25.190.0/spack/unified/0.10.1/install/linux-sles15-x86_64/gcc-13.3.0/llvm-develop-git.5708851-4ulhk4d/bin/clang
            -DCMAKE_CXX_COMPILER=/opt/aurora/25.190.0/spack/unified/0.10.1/install/linux-sles15-x86_64/gcc-13.3.0/llvm-develop-git.5708851-4ulhk4d/bin/clang++
            -DLLVM_ENABLE_LLD=ON
            -DLLVM_OPTIMIZED_TABLEGEN=ON
            -DMLIR_ENABLE_BINDINGS_PYTHON=OFF
            -DLLVM_TARGETS_TO_BUILD="$LLVM_TARGETS"
            -DCMAKE_EXPORT_COMPILE_COMMANDS=1
            -DLLVM_ENABLE_PROJECTS="$LLVM_PROJECTS"
            -DCMAKE_INSTALL_PREFIX="$LLVM_INSTALL_PATH"
            -DCUDA_TOOLKIT_ROOT_DIR:STRING=IGNORE
            -DCUDA_SDK_ROOT_DIR:STRING=IGNORE
            -DCUDA_NVCC_EXECUTABLE:STRING=IGNORE
            -DLIBOMPTARGET_DEP_CUDA_DRIVER_LIBRARIES:STRING=IGNORE
            -DLIBOMPTARGET_ENABLE_DEBUG:BOOL=OFF
            -DLIBOMPTARGET_BUILD_AMDGPU_PLUGIN:BOOL=OFF
            -DRUNTIMES_CMAKE_ARGS:STRING=-DCMAKE_INSTALL_RPATH_USE_LINK_PATH:BOOL=ON
            -DCMAKE_C_FLAGS:STRING=--gcc-install-dir=/opt/aurora/25.190.0/spack/unified/0.10.1/install/linux-sles15-x86_64/gcc-13.3.0/gcc-13.3.0-4enwbrb/lib/gcc/x86_64-pc-linux-gnu/13.3.0
            -DCMAKE_CXX_FLAGS:STRING=--gcc-install-dir=/opt/aurora/25.190.0/spack/unified/0.10.1/install/linux-sles15-x86_64/gcc-13.3.0/gcc-13.3.0-4enwbrb/lib/gcc/x86_64-pc-linux-gnu/13.3.0
            -B"$LLVM_BUILD_PATH" "$LLVM_PROJECT_PATH/llvm"
        )
    else
        CMAKE_ARGS=("$@")
    fi
fi

if [ -n "$LLVM_CLEAN" ] && [ -e "$LLVM_PROJECT_PATH" ]; then
    rm -rf "$LLVM_PROJECT_PATH"
fi

#if [ ! -e "$LLVM_PROJECT_PATH" ]; then
#    echo "Cloning from $LLVM_PROJECT_URL"
#    git clone "$LLVM_PROJECT_URL" "$LLVM_PROJECT_PATH"
#fi
#echo "Resetting to $LLVM_COMMIT_HASH"
#git -C "$LLVM_PROJECT_PATH" fetch origin "$LLVM_COMMIT_HASH"
#git -C "$LLVM_PROJECT_PATH" reset --hard "$LLVM_COMMIT_HASH"
echo "Configuring with ${CMAKE_ARGS[@]}"
cmake "${CMAKE_ARGS[@]}"
echo "Building LLVM"
ninja -C "$LLVM_BUILD_PATH"
