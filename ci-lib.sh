# Common library for frameworks-sdk build scripts

# Loads the necessary environment for component builds.
setup_build_env() {
    module reset
    # module unload oneapi mpich
    # module use /soft/compilers/oneapi/2025.1.3/modulefiles
    # module use /soft/compilers/oneapi/nope/modulefiles
    # module add mpich/nope/develop-git.6037a7a
    # module load cmake

    # TODO: are these needed?
    # unset CMAKE_ROOT
    # export A21_SDK_PTIROOT_OVERRIDE=/home/cchannui/debug5/pti-gpu-test/tools/pti-gpu/d5c2e2e
    # module add oneapi/public/2025.1.3
    #======================================================
    # [2025-07-06][NOTE][sam]: Not exported elsewhere (??)
    # export ZE_FLAT_DEVICE_HIERARCHY=FLAT
    #======================================================
}

# Generates a tmpdir and pulls a Git repo.
gen_build_dir_with_git() {
    pushd "$(mktemp -d)"
    git clone --depth=1 --recurse-submodules "$@"
}

# Sets up a `uv venv` in `$PWD` and installs passed dependencies.
setup_uv_venv() {
    # TODO Switch to `uv sync` and `uv build` for wheel compilation? There are
    # problems building with uv directly if the project has a poorly-written
    # pyproject.toml or expects build dependencies to be installed via pip
    # manually before or during compilation.
    uv venv --python 3.12
    uv pip install --no-cache --link-mode=copy "$@"
}

# Build a bdist wheel from a source directory.
build_bdist_wheel() {
    # We directly invoke `setup.py` so we can use our custom venvs.
    source .venv/bin/activate
    python setup.py bdist_wheel
    deactivate
}

# Archives built artifacts in a given directory to `$PWD`.
archive_artifacts() {
    pushd
    OUT_DIR="$PWD"
    pushd

    find "$1" -type f -name "*.whl" -print0 | xargs -0 cp --target-directory="$OUT_DIR"
}

# Cleans up the given build directory.
cleanup_build_dir() {
    BUILD_DIR="$PWD"
    popd
    rm -rf "$BUILD_DIR"
}

# vim: ts=4:sw=4:expandtab
