#!/usr/bin/env bash
# Copyright (C) 2025-2026 Nathan S. Nichols
# License MIT [https://opensource.org/licenses/MIT]

# ccl_local_wrap.sh
#
# Sets CCL_LOCAL_RANK and CCL_LOCAL_SIZE from common launcher env vars, then execs a command.
# Extended to also set torchrun-style env vars needed by vLLM external_launcher:
#   RANK, WORLD_SIZE, LOCAL_RANK, MASTER_ADDR, MASTER_PORT
#
# Supported sources (in precedence order):
#   - Pre-set CCL_* (respected if already exported)

set -euo pipefail

print_only=false
if [[ "${1-}" == "--print" ]]; then
  print_only=true
  shift
fi

display_help() {
  cat <<EOF
Sets CCL_LOCAL_RANK and CCL_LOCAL_SIZE (oneCCL), plus RANK/WORLD_SIZE/LOCAL_RANK and MASTER_ADDR/MASTER_PORT (vLLM external launcher), then runs a command.

Usage:
  mpiexec -np N -env PALS_WORLD_SIZE=N ./ccl_local_wrap.sh [--print] ./your_app [args...]

--print   Show resolved values and the command before exec.

Notes:
  - Provide PALS_WORLD_SIZE via mpiexec -env PALS_WORLD_SIZE=<world>
  - You may also export MASTER_ADDR/MASTER_PORT before launch for multi-node.
EOF
  exit 1
}

if [[ "$#" -eq 0 ]] || [[ "${1-}" == "--help" ]] || [[ "${1-}" == "-h" ]]; then
  display_help
fi

# --- Helpers ---------------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

slurm_tasks_per_this_node() {
  local tpn="${SLURM_TASKS_PER_NODE-}"
  local nodeid="${SLURM_NODEID-}"
  [[ -z "$tpn" ]] && { echo ""; return; }

  local expanded=""
  IFS=',' read -r -a parts <<< "$tpn"
  for p in "${parts[@]}"; do
    if [[ "$p" =~ ^([0-9]+)\(x([0-9]+)\)$ ]]; then
      local cnt="${BASH_REMATCH[1]}"
      local times="${BASH_REMATCH[2]}"
      for ((i=0; i<times; i++)); do
        expanded+="${cnt},"
      done
    elif [[ "$p" =~ ^([0-9]+)$ ]]; then
      expanded+="${p},"
    fi
  done
  expanded="${expanded%,}"

  if [[ -n "${nodeid}" && "${nodeid}" =~ ^[0-9]+$ ]]; then
    IFS=',' read -r -a ex <<< "$expanded"
    if (( nodeid < ${#ex[@]} )); then
      echo "${ex[$nodeid]}"
      return
    fi
  fi

  if [[ "$tpn" =~ ^([0-9]+)(\(x[0-9]+\))?$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return
  fi

  echo ""
}

# --- Resolve local rank ----------------------------------------------------

resolve_local_rank() {
  if [[ -n "${CCL_LOCAL_RANK-}" ]]; then echo "$CCL_LOCAL_RANK"; return; fi
  if [[ -n "${OMPI_COMM_WORLD_LOCAL_RANK-}" ]]; then echo "$OMPI_COMM_WORLD_LOCAL_RANK"; return; fi
  if [[ -n "${I_MPI_LOCAL_RANK-}" ]]; then echo "$I_MPI_LOCAL_RANK"; return; fi
  if [[ -n "${PMI_LOCAL_RANK-}" ]]; then echo "$PMI_LOCAL_RANK"; return; fi
  if [[ -n "${MPI_LOCALRANKID-}" ]]; then echo "$MPI_LOCALRANKID"; return; fi
  if [[ -n "${PALS_LOCAL_RANKID-}" ]]; then echo "$PALS_LOCAL_RANKID"; return; fi
  if [[ -n "${SLURM_LOCALID-}" ]]; then echo "$SLURM_LOCALID"; return; fi
  echo ""
}

# --- Resolve local size ----------------------------------------------------

resolve_local_size() {
  if [[ -n "${CCL_LOCAL_SIZE-}" ]]; then echo "$CCL_LOCAL_SIZE"; return; fi
  if [[ -n "${OMPI_COMM_WORLD_LOCAL_SIZE-}" ]]; then echo "$OMPI_COMM_WORLD_LOCAL_SIZE"; return; fi
  if [[ -n "${I_MPI_LOCAL_SIZE-}" ]]; then echo "$I_MPI_LOCAL_SIZE"; return; fi
  if [[ -n "${PMI_LOCAL_SIZE-}" ]]; then echo "$PMI_LOCAL_SIZE"; return; fi
  if [[ -n "${MPI_LOCALNRANKS-}" ]]; then echo "$MPI_LOCALNRANKS"; return; fi
  if [[ -n "${PALS_LOCAL_SIZE-}" ]]; then echo "$PALS_LOCAL_SIZE"; return; fi

  if [[ -n "${SLURM_LOCALID-}" ]]; then
    local tpn="$(slurm_tasks_per_this_node)"
    if [[ -n "$tpn" ]]; then echo "$tpn"; return; fi
  fi

  echo ""
}

LOCAL_RANK_CCL="$(resolve_local_rank)"
LOCAL_SIZE_CCL="$(resolve_local_size)"

if [[ -z "$LOCAL_RANK_CCL" || -z "$LOCAL_SIZE_CCL" ]]; then
  echo "ERROR: Could not determine CCL_LOCAL_RANK/CCL_LOCAL_SIZE from environment." >&2
  echo "Hint: Are you launching with mpiexec/srun and per-node ranks visible?" >&2
  display_help
fi

export CCL_LOCAL_RANK="$LOCAL_RANK_CCL"
export CCL_LOCAL_SIZE="$LOCAL_SIZE_CCL"
export CCL_PROCESS_LAUNCHER=none

# --- NEW: Resolve torchrun-style env for vLLM external_launcher ------------

resolve_world_rank() {
  if [[ -n "${RANK-}" ]]; then echo "$RANK"; return; fi
  if [[ -n "${PALS_RANKID-}" ]]; then echo "$PALS_RANKID"; return; fi
  if [[ -n "${PMIX_RANK-}" ]]; then echo "$PMIX_RANK"; return; fi
  if [[ -n "${OMPI_COMM_WORLD_RANK-}" ]]; then echo "$OMPI_COMM_WORLD_RANK"; return; fi
  if [[ -n "${PMI_RANK-}" ]]; then echo "$PMI_RANK"; return; fi
  if [[ -n "${SLURM_PROCID-}" ]]; then echo "$SLURM_PROCID"; return; fi
  echo ""
}

resolve_world_size() {
  if [[ -n "${WORLD_SIZE-}" ]]; then echo "$WORLD_SIZE"; return; fi
  # You requested PALS_WORLD_SIZE as the source of truth.
  if [[ -n "${PALS_WORLD_SIZE-}" ]]; then echo "$PALS_WORLD_SIZE"; return; fi
  if [[ -n "${OMPI_COMM_WORLD_SIZE-}" ]]; then echo "$OMPI_COMM_WORLD_SIZE"; return; fi
  if [[ -n "${PMI_SIZE-}" ]]; then echo "$PMI_SIZE"; return; fi
  if [[ -n "${SLURM_NTASKS-}" ]]; then echo "$SLURM_NTASKS"; return; fi
  echo ""
}

resolve_local_rank_for_torch() {
  if [[ -n "${LOCAL_RANK-}" ]]; then echo "$LOCAL_RANK"; return; fi
  if [[ -n "${PALS_LOCAL_RANKID-}" ]]; then echo "$PALS_LOCAL_RANKID"; return; fi
  # Fall back to the same local rank we computed for CCL.
  echo "$CCL_LOCAL_RANK"
}

# Master address: prefer user-provided; otherwise safe fallback.
resolve_master_addr() {
  if [[ -n "${MASTER_ADDR-}" ]]; then echo "$MASTER_ADDR"; return; fi
  # Single node: hostname is fine. Multi-node: user should export MASTER_ADDR externally.
  hostname
}

WORLD_RANK="$(resolve_world_rank)"
WORLD_SIZE="$(resolve_world_size)"
LOCAL_RANK_TORCH="$(resolve_local_rank_for_torch)"

if [[ -z "$WORLD_RANK" || -z "$WORLD_SIZE" ]]; then
  echo "ERROR: Could not determine RANK/WORLD_SIZE for external launcher." >&2
  echo "Hint: PALS_RANKID/PMIX_RANK must be set, and pass -env PALS_WORLD_SIZE=<N> to mpiexec." >&2
  display_help
fi

export RANK="$WORLD_RANK"
export WORLD_SIZE="$WORLD_SIZE"
export LOCAL_RANK="$LOCAL_RANK_TORCH"
export MASTER_ADDR="$(resolve_master_addr)"
export MASTER_PORT="${MASTER_PORT:-29500}"

export TMPDIR=/tmp
export VLLM_RPC_BASE_PATH=/tmp/vllm_ipc
mkdir -p "$VLLM_RPC_BASE_PATH"
export VLLM_CACHE_ROOT="${VLLM_CACHE_ROOT:-/tmp/.vllm_cache}"
mkdir -p "$VLLM_CACHE_ROOT"

export TRITON_CACHE_DIR=/tmp/triton_cache
export TRITON_HOME=/tmp/triton_home
mkdir -p "$TRITON_CACHE_DIR"
mkdir -p "$TRITON_HOME"

#https://github.com/intel/compute-runtime/blob/master/programmers-guide/COMPILER_CACHE.md
export NEO_CACHE_PERSISTENT=1
export NEO_CACHE_DIR=/tmp/neo_cache
mkdir -p "$NEO_CACHE_DIR"
export NEO_CACHE_MAX_SIZE=0

if $print_only; then
  echo "CCL_LOCAL_RANK=$CCL_LOCAL_RANK"
  echo "CCL_LOCAL_SIZE=$CCL_LOCAL_SIZE"
  echo "CCL_PROCESS_LAUNCHER=$CCL_PROCESS_LAUNCHER"
  echo "RANK=$RANK"
  echo "WORLD_SIZE=$WORLD_SIZE"
  echo "LOCAL_RANK=$LOCAL_RANK"
  echo "MASTER_ADDR=$MASTER_ADDR"
  echo "MASTER_PORT=$MASTER_PORT"
  echo "Command: $*"
fi

exec "$@"

