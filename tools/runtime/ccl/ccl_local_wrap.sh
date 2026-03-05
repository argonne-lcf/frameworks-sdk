#!/usr/bin/env bash
# Copyright (C) 2025-2026 Nathan S. Nichols
# License MIT [https://opensource.org/licenses/MIT]
# ccl_local_wrap.sh
#
# Sets CCL_LOCAL_RANK and CCL_LOCAL_SIZE from common launcher env vars, then execs a command.
# Supported sources (in precedence order):
#   - Pre-set CCL_* (respected if already exported)
#   - Open MPI:           OMPI_COMM_WORLD_LOCAL_RANK / OMPI_COMM_WORLD_LOCAL_SIZE
#   - Intel MPI:          I_MPI_LOCAL_RANK / I_MPI_LOCAL_SIZE
#   - MPICH / PMI2:       PMI_LOCAL_RANK / PMI_LOCAL_SIZE
#   - Generic MPI:        MPI_LOCALRANKID / MPI_LOCALNRANKS (if available)
#   - PALS:               PALS_LOCAL_RANKID / PALS_LOCAL_SIZE
#   - SLURM (srun/mpirun): SLURM_LOCALID / SLURM_NTASKS_PER_NODE (best-effort parse)
#
# Usage:
#   mpiexec -np N ./ccl_local_wrap.sh [--print] ./your_app [args...]
#
# Tips:
#   - Use --print to echo the resolved values before exec.
#   - If neither local rank nor local size can be determined, the script exits with help.

set -euo pipefail

print_only=false
if [[ "${1-}" == "--print" ]]; then
  print_only=true
  shift
fi

display_help() {
  cat <<EOF
Sets CCL_LOCAL_RANK and CCL_LOCAL_SIZE from your job launcher, then runs a command.

Usage:
  mpiexec -np N ccl_local_wrap.sh [--print] ./a.out [args...]

Environment sources (in precedence):
  OMPI_COMM_WORLD_LOCAL_RANK / OMPI_COMM_WORLD_LOCAL_SIZE
  I_MPI_LOCAL_RANK / I_MPI_LOCAL_SIZE
  PMI_LOCAL_RANK / PMI_LOCAL_SIZE
  MPI_LOCALRANKID / MPI_LOCALNRANKS
  PALS_LOCAL_RANKID / PALS_LOCAL_SIZE
  SLURM_LOCALID / SLURM_NTASKS_PER_NODE (best-effort)

--print   Show resolved values and the command before exec.

Examples:
  mpiexec -np 8 ./ccl_local_wrap.sh ./a.out
  srun -N 2 -n 16 ./ccl_local_wrap.sh --print ./a.out
EOF
  exit 1
}

if [[ "$#" -eq 0 ]] || [[ "${1-}" == "--help" ]] || [[ "${1-}" == "-h" ]]; then
  display_help
fi

# --- Helpers ---------------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

# Parse SLURM_NTASKS_PER_NODE into an integer for *this* node when possible.
# Common formats:
#   "8"                      -> 8
#   "8(x2)"                  -> ambiguous per node; if uniform, returns 8
#   "8,4"                    -> first node 8, second 4 (we use SLURM_NODEID to pick)
#   "8(x2),4"                -> expand counts using repeats, pick by SLURM_NODEID
slurm_tasks_per_this_node() {
  local tpn="${SLURM_TASKS_PER_NODE-}"
  local nodeid="${SLURM_NODEID-}"
  [[ -z "$tpn" ]] && { echo ""; return; }

  # Expand "8(x2),4,2(x3)" -> "8,8,4,2,2,2"
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

  # If SLURM_NODEID present, pick that index; else if list is uniform length 1, return it
  if [[ -n "${nodeid}" && "${nodeid}" =~ ^[0-9]+$ ]]; then
    IFS=',' read -r -a ex <<< "$expanded"
    if (( nodeid < ${#ex[@]} )); then
      echo "${ex[$nodeid]}"
      return
    fi
  fi

  # Fall back: if original is a single integer like "8" or uniform "X(xN)" -> return first number
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

  # SLURM best-effort
  if [[ -n "${SLURM_LOCALID-}" ]]; then
    local tpn="$(slurm_tasks_per_this_node)"
    if [[ -n "$tpn" ]]; then echo "$tpn"; return; fi
  fi

  echo ""
}

LOCAL_RANK="$(resolve_local_rank)"
LOCAL_SIZE="$(resolve_local_size)"

if [[ -z "$LOCAL_RANK" || -z "$LOCAL_SIZE" ]]; then
  echo "ERROR: Could not determine CCL_LOCAL_RANK/CCL_LOCAL_SIZE from environment." >&2
  echo "Hint: Are you launching with mpiexec/srun and per-node ranks visible?" >&2
  display_help
fi

export CCL_LOCAL_RANK="$LOCAL_RANK"
export CCL_LOCAL_SIZE="$LOCAL_SIZE"
export CCL_PROCESS_LAUNCHER=none

if $print_only; then
  echo "CCL_LOCAL_RANK=$CCL_LOCAL_RANK"
  echo "CCL_LOCAL_SIZE=$CCL_LOCAL_SIZE"
  echo "Command: $*"
fi

exec "$@"
