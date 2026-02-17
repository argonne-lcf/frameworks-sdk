# Common library for frameworks-sdk build scripts
# shellcheck shell=bash

set -x          # command trace
set -e          # non-zero exit
set -u          # fail on unset env var
set -o pipefail # pipe return last err

FRAMEWORKS_SDK_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

if [ -v GITLAB_CI ]; then
	FRAMEWORKS_RUN_DIR="$FRAMEWORKS_ROOT_DIR/$CI_PIPELINE_ID"
else
	FRAMEWORKS_RUN_DIR="$FRAMEWORKS_ROOT_DIR/$(whoami)"
fi

# Loads the necessary environment for component builds.
setup_build_env() {
	module reset
	case "$(hostname -f)" in
	*"sunspot.alcf.anl.gov")
		module load cmake # `cmake` not in the system path on Sunspot
		;;
	esac

	# global MAX_JOBS for {torch, ipex}
	export MAX_JOBS=48

	# configure `uv`
	export UV_PYTHON_VERSION="$FRAMEWORKS_PYTHON_VERSION"
	# User home disk quota fills up w/ caching if not on project allocation
	export UV_CACHE_DIR="$FRAMEWORKS_ROOT_DIR/uv-cache"
	# Lustre doesn't support hardlinks
	export UV_LINK_MODE="copy"

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
	section_start "gen_build_dir_with_git[collapsed=true]"

	pushd "$(mktemp -d)"
	git clone --depth=1 --recurse-submodules "$@" .
	trap cleanup_build_dir 0

	section_end "gen_build_dir_with_git[collapsed=true]"
}

# Sets up a `uv venv` in `$PWD` and installs passed dependencies.
setup_uv_venv() {
	section_start "setup_uv_venv[collapsed=true]"

	# TODO Switch to `uv sync` and `uv build` for wheel compilation? There are
	# problems building with uv directly if the project has a poorly-written
	# pyproject.toml or expects build dependencies to be installed via pip
	# manually before or during compilation.
	uv venv
	if [ "$#" -gt 0 ]; then
		uv pip install "$@"
	fi

	section_end "setup_uv_venv[collapsed=true]"
}

# Build a bdist wheel from a source directory.
build_bdist_wheel() {
	section_start "build_bdist_wheel[collapsed=true]"

	# We directly invoke `setup.py` so we can use our custom venvs.
	# shellcheck source=/dev/null
	source .venv/bin/activate
	python setup.py bdist_wheel > build_bdist_wheel.log 2>&1
	deactivate

	section_end "build_bdist_wheel[collapsed=true]"

	# Copy out wheels afterwards
	artifact_out "*.whl"
}

# Copies artifacts from the per-run `$FRAMEWORKS_ROOT_DIR` to `$PWD`.
artifact_in() {
	find "$FRAMEWORKS_RUN_DIR" -type f -name "$1" -print0 | xargs -0 cp -t .
}

# Copies artifacts from the build tmpdir to `$FRAMEWORKS_ROOT_DIR`.
artifact_out() {
	find . -type f -name "$1" -print0 | xargs -0 install --backup=numbered -C -D -t "$FRAMEWORKS_RUN_DIR"
}

# Cleans up the build tmpdir and archives built artifacts to `$PWD`.
cleanup_build_dir() {
	TMP_DIR="$(realpath .)"

	# Always pull log files
	artifact_out "build_bdist_wheel.log" 2>/dev/null || true
	popd
	artifact_in "*.log" 2>/dev/null || true

	rm -rf "$TMP_DIR"
}

# Start a collapsible section in the GitLab log.
section_start() {
	echo -e "\e[0Ksection_start:$(date +%s):$1\r\e[0K${2:-${1%[\[]*}}"
}

# End a collapsible section in the GitLab log.
section_end() {
	echo -e "\e[0Ksection_end:$(date +%s):${1%[\[]*}\r\e[0K"
}
