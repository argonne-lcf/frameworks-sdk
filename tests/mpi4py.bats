setup() {
	# Load prereqs
	load 'test_helper/bats-support/load'
	load 'test_helper/bats-assert/load'
	load 'test_helper/test-lib.bats'
}

@test "mpi4py/sanity" {
	./tests/single_node/functionality/mpi4py/sanity.sh
}

@test "mpi4py/test" {
	spawn_job -q debug -A datascience -N 1 -t 01:00:00 -f home:flare <<EOF
source "$(dirname "$(realpath "$BATS_TEST_FILENAME")")/../ci-lib.sh"
setup_build_env

gen_build_dir_with_git 'https://github.com/mpi4py/mpi4py'

# Setup ephemeral uv venv
artifact_in "mpi4py*.whl"
setup_uv_venv *.whl

# Run testsuite
uv run --no-sync -- python test/main.py -v
EOF
}
