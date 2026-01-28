# Common library for frameworks-sdk build scripts

set -x # command trace
set -e # non-zero exit
set -u # fail on unset env var
set -o pipefail # pipe return last err

# Loads the necessary environment for component builds.
setup_build_env() {
    module reset
    case "$(hostname -f)" in
        (*"sunspot.alcf.anl.gov")
            module load cmake;; # `cmake` not in the system path on Sunspot
    esac

    # global MAX_JOBS for {torch, ipex}
    export MAX_JOBS=48

    export DEFAULT_PYTHON_VERSION="${DEFAULT_PYTHON_VERSION:-3.12}"

    # module unload oneapi mpich
    # module use /soft/compilers/oneapi/2025.1.3/modulefiles
    # module use /soft/compilers/oneapi/nope/modulefiles
    # module add mpich/nope/develop-git.6037a7a

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
    git clone --depth=1 --recurse-submodules "$@" .
    trap cleanup_build_dir 0
}

# Sets up a `uv venv` in `$PWD` and installs passed dependencies.
setup_uv_venv() {
    # TODO Switch to `uv sync` and `uv build` for wheel compilation? There are
    # problems building with uv directly if the project has a poorly-written
    # pyproject.toml or expects build dependencies to be installed via pip
    # manually before or during compilation.
    uv venv --python "$DEFAULT_PYTHON_VERSION"
    if [ "$#" -gt 0 ]; then
        # FIXME user home disk quota fills up w/ caching
        # Lustre doesn't support hardlinks
        uv pip install --no-cache --link-mode=copy "$@"
    fi
}

# Build a bdist wheel from a source directory.
build_bdist_wheel() {
    # We directly invoke `setup.py` so we can use our custom venvs.
    source .venv/bin/activate
    python setup.py bdist_wheel |& tee build_bdist_wheel.log
    deactivate
}

# Cleans up the build tmpdir and archives built artifacts to `$PWD`.
cleanup_build_dir() {
    TMP_DIR="$PWD"
    popd

    find "$TMP_DIR" -type f \( -name "*.whl" -o -name "build_bdist_wheel.log" \) -print0 | xargs -0 cp -t "$PWD"
    rm -rf "$TMP_DIR"
}

# vim: ts=4:sw=4:expandtab
