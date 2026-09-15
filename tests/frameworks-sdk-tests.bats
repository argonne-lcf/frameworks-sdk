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

gen_build_dir_with_git "$FRAMEWORKS_ROOT_DIR/frameworks-sdk-tests" -b "$FRAMEWORKS_SDK_TESTS_VERSION"

# Make the pipeline's modulefile visible to the runner
module use "\$FRAMEWORKS_RUN_DIR/modulefiles"

# Run the suite; the runner loads the module itself and records it in the
# summary. Write results to the workspace (the tmpdir is deleted on cleanup)
# so they can be converted to JUnit XML for GitLab CI ingestion
./run_tests run --module frameworks-sdk --suite "$suite" --results-dir "$PWD/results"
EOF
}

# Runs the multi-node torch collective fabric tests in a PBS job against the
# wheels built by this pipeline.
run_multi_node_collectives() {
	spawn_job "$@" <<EOF
source "$(dirname "$(realpath "$BATS_TEST_FILENAME")")/../ci-lib.sh"

gen_build_dir_with_git "$FRAMEWORKS_ROOT_DIR/frameworks-sdk-tests" -b "$FRAMEWORKS_SDK_TESTS_VERSION"

# Make the pipeline's modulefile visible to the launcher
module use "\$FRAMEWORKS_RUN_DIR/modulefiles"

status=0
for test_case in allreduce allgather alltoall alltoall_uneven reduce_scatter overlap p2p subgroups; do
	echo "=== multi-node collective: \$test_case ==="
	if ! FRAMEWORKS_MODULE=frameworks-sdk TEST_CASE="\$test_case" bash ./scripts/run_torch_collective_pbs.sh; then
		status=1
	fi
done
exit "\$status"
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

@test "frameworks-sdk-tests/multi-node-collectives" {
	run_multi_node_collectives -q "$(long_queue)" -N 2 -t 04:00:00
}
