setup() {
	# Load prereqs
	load 'test_helper/bats-support/load'
	load 'test_helper/bats-assert/load'
	load 'test_helper/test-lib.bats'
}

# Runs a single frameworks-sdk-tests suite in a PBS job. Extra arguments are
# forwarded to `spawn_job` (nodes, walltime, filesystems, ...).
run_frameworks_sdk_tests_suite() {
	local suite="$1"
	shift

	spawn_job "$@" <<EOF
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
# The PyPI dpctl/dpnp wheels bundle a newer oneAPI/UR runtime than the loaded
# module env provides, and LD_LIBRARY_PATH outranks their RUNPATH, so the
# venv's bundled (self-consistent) runtime must come first.
export LD_LIBRARY_PATH="\$PWD/.venv/lib:\$FRAMEWORKS_RUN_DIR/pti-gpu/lib:\$LD_LIBRARY_PATH"

# Run the suite; write results to the workspace (the tmpdir is deleted on
# cleanup) so they can be converted to JUnit XML for GitLab CI ingestion
uv run --no-sync -- ./run_tests run --no-module --suite "$suite" --results-dir "$PWD/results"
EOF
}

@test "frameworks-sdk-tests/smoke" {
	run_frameworks_sdk_tests_suite smoke -N 1 -t 01:00:00
}

@test "frameworks-sdk-tests/harness" {
	run_frameworks_sdk_tests_suite harness -q "$(long_queue)" -N 1 -t 02:00:00
}

@test "frameworks-sdk-tests/distributed" {
	run_frameworks_sdk_tests_suite distributed -q "$(long_queue)" -N 1 -t 04:00:00
}

@test "frameworks-sdk-tests/regression" {
	run_frameworks_sdk_tests_suite regression -q "$(long_queue)" -N 1 -t 08:00:00
}

@test "frameworks-sdk-tests/workload" {
	run_frameworks_sdk_tests_suite workload -q "$(long_queue)" -N 1 -t 08:00:00
}

@test "frameworks-sdk-tests/benchmark" {
	run_frameworks_sdk_tests_suite benchmark -q "$(long_queue)" -N 1 -t 04:00:00
}
