#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

export ZE_FLAT_DEVICE_HIERARCHY="${ZE_FLAT_DEVICE_HIERARCHY:-FLAT}"
export TENSOR_SIZE="${TENSOR_SIZE:-100000000}"
export MAX_ITERS="${MAX_ITERS:-30}"
export LOG_EVERY="${LOG_EVERY:-10}"
export MASTER_ADDR="${MASTER_ADDR:-127.0.0.1}"

run_mode() {
  local mode="$1"
  local port="$2"
  echo
  echo "=== MODE=${mode} ==="
  MASTER_PORT="$port" MODE="$mode" \
    mpiexec -n 2 -ppn 2 -env PALS_WORLD_SIZE=2 -env ROOT=$ROOT -- bash -lc '
      export RANK=$PALS_RANKID WORLD_SIZE=$PALS_WORLD_SIZE
      export LOCAL_RANK=$PALS_LOCAL_RANKID LOCAL_WORLD_SIZE=$PALS_LOCAL_SIZE
      python -u $ROOT/prove_list_allgather_hidden_temp.py
    '
}

run_mode list_hidden_temp 2620
run_mode into_persistent 2621
run_mode explicit_temp 2622
run_mode temp_no_collective 2623
