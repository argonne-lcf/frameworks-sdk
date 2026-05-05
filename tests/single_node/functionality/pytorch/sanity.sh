#!/bin/sh
source "$(dirname "$(realpath "$BATS_TEST_FILENAME")")/../ci-lib.sh"

TMPDIR="$(mktemp -d)"
trap "rm -rf $TMPDIR" 0
pushd "$TMPDIR"

# Setup ephemeral uv venv
artifact_in "torch*.whl"
setup_uv_venv *.whl

# Sanity check that the wheel loads
uv run -- python <<EOF
import torch
import torch.distributed

device_count = torch.xpu.device_count()

print(torch.__file__)
print(*torch.__config__.show().split("\n"), sep="\n")

print(f"PyTorch: {torch.__version__=}")
print(f"XPU: {torch.xpu.is_available()=} ({device_count=})")
print(f"XCCL: {torch.distributed.is_xccl_available()=}")

for i in range(device_count):
    print(f"torch.xpu.get_device_properties({i}): {torch.xpu.get_device_properties(i)}")
EOF

popd
