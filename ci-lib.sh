# Common library for frameworks-sdk build scripts

# Loads the necessary environment for component builds.
setup_build_env() {
    module restore
    module unload oneapi mpich
    module use /soft/compilers/oneapi/2025.1.3/modulefiles
    module use /soft/compilers/oneapi/nope/modulefiles
    module add mpich/nope/develop-git.6037a7a
    module load cmake

    # TODO: are these needed?
    unset CMAKE_ROOT
    export A21_SDK_PTIROOT_OVERRIDE=/home/cchannui/debug5/pti-gpu-test/tools/pti-gpu/d5c2e2e
    module add oneapi/public/2025.1.3
    #======================================================
    # [2025-07-06][NOTE][sam]: Not exported elsewhere (??)
    export ZE_FLAT_DEVICE_HIERARCHY=FLAT
    #======================================================
}

# Generates a tmpdir and pulls a Git repo.
gen_build_dir_with_git() {
    BUILD_DIR="$(mktemp -d)"
    pushd "$BUILD_DIR"

    # TODO shallow clone this!
    git clone "$@"
    pushd "$(basename $_ .git)"
    git submodule update --init --recursive
    popd

    echo "$BUILD_DIR"
}

# Build a bdist wheel from a source directory.
build_bdist_wheel() {
    uv build --wheel "$1"
}

# Cleans up the given build directory.
cleanup_build_dir() {
    popd
    rm -rf "$1"
}

# vim: ts=4:sw=4:expandtab
