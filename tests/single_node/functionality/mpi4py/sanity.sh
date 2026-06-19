#!/bin/sh
source "$(dirname "$(realpath "$BATS_TEST_FILENAME")")/../ci-lib.sh"

TMPDIR="$(mktemp -d)"
trap "rm -rf $TMPDIR" 0
pushd "$TMPDIR"

# Setup ephemeral uv venv
artifact_in "mpi4py*.whl"
setup_uv_venv *.whl

# Sanity check that the wheel loads
uv run -- python <<EOF
import mpi4py
print(mpi4py.get_config())
EOF

popd
