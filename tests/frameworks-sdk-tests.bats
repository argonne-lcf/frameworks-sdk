setup() {
	# Load prereqs
	load 'test_helper/bats-support/load'
	load 'test_helper/bats-assert/load'
	load 'test_helper/test-lib.bats'
}

@test "frameworks-sdk-tests/smoke" {
	spawn_job -N 1 -t 01:00:00 <<EOF
source "$(dirname "$(realpath "$BATS_TEST_FILENAME")")/../ci-lib.sh"
setup_build_env

gen_build_dir_with_git "$FRAMEWORKS_ROOT_DIR/frameworks-sdk-tests" -b "$FRAMEWORKS_SDK_TESTS_VERSION"

# Setup ephemeral uv venv
artifact_in "torch-*.whl"
artifact_in "torchvision-*.whl"
artifact_in "mpi4py*.whl"
setup_uv_venv *.whl

# 'smoke' suite also checks dpctl/dpnp, which we do not build
# TODO: build dpctl, dpnp?
uv pip install dpctl dpnp

# Load pti-gpu
# The PyPI `dpctl`/`dpnp` wheels bundle a newer oneAPI/UR runtime than the
# loaded module env provides, and `LD_LIBRARY_PATH` outranks their `RUNPATH`,
# so the venv's bundled (self-consistent) runtime must come first.
export LD_LIBRARY_PATH="\$PWD/.venv/lib:\$FRAMEWORKS_RUN_DIR/pti-gpu/lib:\$LD_LIBRARY_PATH"

# Run smoke suite; write results to the workspace (the tmpdir is deleted on
# cleanup) so they can be converted to JUnit XML for GitLab CI ingestion
uv run --no-sync -- ./run_tests run --no-module --suite smoke --results-dir "$PWD/results"
EOF
}
