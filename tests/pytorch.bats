setup() {
	# Load prereqs
	load 'test_helper/bats-support/load'
	load 'test_helper/bats-assert/load'
	load 'test_helper/test-lib.bats'
}

@test "pytorch/test" {
	spawn_job -q debug -A datascience -N 1 -t 01:00:00 -f home:flare <<EOF
source "$(dirname "$(realpath "$BATS_TEST_FILENAME")")/../ci-lib.sh"
setup_build_env

gen_build_dir_with_git https://github.com/pytorch/pytorch -b "$FRAMEWORKS_TORCH_VERSION"

# Setup ephemeral uv venv
artifact_in "torch*.whl"
setup_uv_venv -r .ci/docker/requirements-ci.txt *.whl

# Run testsuite
uv run --no-sync -- ./test/run_test.py --core --keep-going
EOF
}
