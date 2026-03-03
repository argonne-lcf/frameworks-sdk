setup() {
	# Load prereqs
	load 'test_helper/bats-support/load'
	load 'test_helper/bats-assert/load'
	source "$(dirname "$(realpath "$BATS_TEST_FILENAME")")/../ci-lib.sh"
	set +x # re-disable command trace after loading `ci-lib.sh`
	setup_build_env
}

@test "pytorch/test" {
	git clone --depth=1 https://github.com/pytorch/pytorch -b "$FRAMEWORKS_TORCH_VERSION"
	cd pytorch

	# Setup ephemeral uv venv
	artifact_in "torch*.whl"
	setup_uv_venv -r .ci/docker/requirements-ci.txt *.whl

	# Run testsuite
	uv run --no-sync -- ./test/run_test.py --core --keep-going
}

teardown_file() {
	rm -rf pytorch
}
