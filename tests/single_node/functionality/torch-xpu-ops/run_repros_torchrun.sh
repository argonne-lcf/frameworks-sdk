#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

export ZE_FLAT_DEVICE_HIERARCHY="${ZE_FLAT_DEVICE_HIERARCHY:-FLAT}"
export TENSOR_SIZE="${TENSOR_SIZE:-100000000}"
export MAX_ITERS="${MAX_ITERS:-30}"
export LOG_EVERY="${LOG_EVERY:-10}"
export SKIP_EXIT_ON_FAIL="${SKIP_EXIT_ON_FAIL:-1}"

run_mode() {
  local mode="$1"
  echo
  echo "=== MODE=${mode} ==="
  MODE="$mode" torchrun --standalone --nnodes=1 --nproc-per-node=2 \
    $ROOT/prove_list_allgather_hidden_temp.py
}

run_mode list_hidden_temp
run_mode into_persistent
run_mode explicit_temp
run_mode temp_no_collective
