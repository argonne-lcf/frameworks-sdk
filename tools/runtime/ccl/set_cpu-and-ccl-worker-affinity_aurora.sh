#!/bin/bash
# Copyright (C) 2024-2026 Nathan S. Nichols
# License MIT [https://opensource.org/licenses/MIT]

# -----------------------------
# Topology / mapping assumptions
# -----------------------------
# Physical core IDs:
#   Socket 0: 0-51   (but core 0 is disabled -> usable 1-51)
#   Socket 1: 52-103 (but core 52 is disabled -> usable 53-103)
#
# Logical core IDs are: physical_core + 104
#   Socket 0 logical usable: 105-155
#   Socket 1 logical usable: 157-207

cores_per_socket_physical=52
sockets=2

socket0_base=0
socket1_base=52

# Disabled physical cores (one per socket)
disabled_core_socket0=0
disabled_core_socket1=52

# Logical offset (logical = physical + 104)
logical_offset=104

# Usable physical cores per socket (52 - 1 disabled)
usable_physical_per_socket=$((cores_per_socket_physical - 1))

# -----------------------------
# Optional flags
# -----------------------------
# DEFAULT: physical-only
include_logical=0
args=()

for a in "$@"; do
  case "$a" in
    --logical|--include-logical)
      include_logical=1
      ;;
    --no-logical|--physical-only)
      include_logical=0
      ;;
    -*)
      echo "Unknown option: $a"
      echo "Usage: $0 <ranks_per_node> [shift_amount] [--logical]"
      exit 1
      ;;
    *)
      args+=("$a")
      ;;
  esac
done

# Check if number of ranks per node is provided
if [ "${#args[@]}" -lt 1 ]; then
    echo "Usage: $0 <ranks_per_node> [shift_amount] [--logical]"
    exit 1
fi

ranks_per_node=${args[0]}
shift_amount=${args[1]:-0} # Default shift amount is 0 if not provided

# -----------------------------
# ranks_per_node == 1 shortcut
# -----------------------------
if [ "$ranks_per_node" -eq 1 ]; then
    # Usable physical ranges: 1-51 and 53-103
    phys="1-51,53-103"

    if [ "$include_logical" -eq 1 ]; then
        # Logical ranges are physical + 104 => 105-155 and 157-207
        log="105-155,157-207"
        cpu_bind_list="${phys},${log}"
    else
        cpu_bind_list="${phys}"
    fi

    # Reserve 1 core per rank from the end (rank=1 => take highest physical core overall)
    # With 1 rank, take the very last physical core on socket1: 103
    ccl_worker_affinity="103"

    echo "--cpu-bind list:$cpu_bind_list"
    echo "export CCL_WORKER_AFFINITY=$ccl_worker_affinity"
    exit 0
fi

# -----------------------------
# Round ranks_per_node up to even
# -----------------------------
was_odd=0
orig_ranks_per_node=${ranks_per_node}
if [ $((ranks_per_node % 2)) -ne 0 ]; then
    ranks_per_node=$((ranks_per_node + 1))
    was_odd=1
fi

ranks_per_socket=$((ranks_per_node / sockets))

# Effective ranks per socket after trimming if original was odd.
# The list is socket0 ":" socket1, then trim the last group -> trims from socket1.
ranks_socket0=$ranks_per_socket
ranks_socket1=$ranks_per_socket
if [ "$was_odd" -eq 1 ]; then
    ranks_socket1=$((ranks_socket1 - 1))
fi

# -----------------------------
# Reserve 1 physical core per rank from the end of each socket
# Build CCL_WORKER_AFFINITY in local rank order:
#   [socket0 ranks..., socket1 ranks...]
# -----------------------------
reserve_worker_cores_for_socket() {
    local socket_base=$1
    local disabled_core=$2
    local count=$3

    local phys_first=$((disabled_core + 1))
    local phys_last=$((socket_base + cores_per_socket_physical - 1))

    local out=()
    local p=$phys_last
    while [ "${#out[@]}" -lt "$count" ] && [ "$p" -ge "$phys_first" ]; do
        out+=("$p")
        p=$((p - 1))
    done

    # Return as space-separated list
    echo "${out[@]}"
}

worker_cores_s0=( $(reserve_worker_cores_for_socket "$socket0_base" "$disabled_core_socket0" "$ranks_socket0") )
worker_cores_s1=( $(reserve_worker_cores_for_socket "$socket1_base" "$disabled_core_socket1" "$ranks_socket1") )

# Join worker cores in rank order into CCL_WORKER_AFFINITY (comma-separated)
ccl_worker_affinity=""
for c in "${worker_cores_s0[@]}" "${worker_cores_s1[@]}"; do
    if [ -z "$ccl_worker_affinity" ]; then
        ccl_worker_affinity="$c"
    else
        ccl_worker_affinity="${ccl_worker_affinity},$c"
    fi
done

# Compute how many physical cores remain for compute per socket after reserving worker cores
compute_physical_s0=$((usable_physical_per_socket - ranks_socket0))
compute_physical_s1=$((usable_physical_per_socket - ranks_socket1))
if [ "$compute_physical_s0" -lt 0 ]; then compute_physical_s0=0; fi
if [ "$compute_physical_s1" -lt 0 ]; then compute_physical_s1=0; fi

# -----------------------------
# Max shift logic (based on remaining usable compute physical cores)
# Use the *smaller* of the two sockets for safety.
# -----------------------------
min_compute_physical=$compute_physical_s0
if [ "$compute_physical_s1" -lt "$min_compute_physical" ]; then
    min_compute_physical=$compute_physical_s1
fi

if [ "$ranks_per_socket" -gt 0 ] && [ "$min_compute_physical" -ge "$ranks_per_socket" ]; then
    cores_per_rank=$((min_compute_physical / ranks_per_socket))
    if [ "$cores_per_rank" -gt 0 ]; then
        max_shift=$((cores_per_rank - 1))
    else
        max_shift=0
    fi
else
    max_shift=0
fi

if [ "$shift_amount" -gt "$max_shift" ]; then
    shift_amount=0
fi

# -----------------------------
# Function to generate CPU ranges for a socket
# Takes the remaining physical cores available for compute on that socket
# and excludes the reserved tail cores.
# -----------------------------
generate_cpu_ranges() {
    local socket_base=$1
    local disabled_core=$2
    local rps=$3
    local compute_phys_count=$4
    local cpu_ranges=""

    local phys_first=$((disabled_core + 1))
    local phys_last_full=$((socket_base + cores_per_socket_physical - 1))

    # Physical cores available to compute are the first (compute_phys_count) cores from phys_first upward,
    # i.e., we exclude the "tail" that we reserved for workers.
    local phys_last_compute=$((phys_first + compute_phys_count - 1))

    # If no physical cores remain for compute, only logical can be used (if enabled)
    if [ "$compute_phys_count" -le 0 ]; then
        if [ "$include_logical" -eq 1 ]; then
            # Give each rank 1 logical core mapped from the corresponding physical numbering
            for (( i=0; i<rps; i++ )); do
                local p=$((phys_first + i))
                local l=$((p + logical_offset))
                cpu_ranges+="$l:"
            done
            echo "${cpu_ranges%:}"
            return
        else
            # Physical-only requested but none left for compute
            # Fall back to 1 physical per rank starting at phys_first (will overlap workers if oversubscribed)
            for (( i=0; i<rps; i++ )); do
                local p=$((phys_first + i))
                cpu_ranges+="$p:"
            done
            echo "${cpu_ranges%:}"
            return
        fi
    fi

    # If ranks exceed remaining physical cores, assign 1 physical per core, then spill to logical if enabled
    if [ "$rps" -gt "$compute_phys_count" ]; then
        for (( i=0; i<compute_phys_count; i++ )); do
            local p=$((phys_first + i))
            cpu_ranges+="$p:"
        done

        if [ "$include_logical" -eq 1 ]; then
            local spill=$((rps - compute_phys_count))
            for (( i=0; i<spill; i++ )); do
                local p=$((phys_first + i))
                local l=$((p + logical_offset))
                cpu_ranges+="$l:"
            done
        fi

        echo "${cpu_ranges%:}"
        return
    fi

    # Normal case: partition remaining physical cores among ranks
    local cores_per_rank=$((compute_phys_count / rps))
    if [ "$cores_per_rank" -lt 1 ]; then cores_per_rank=1; fi

    for (( rank=0; rank<rps; rank++ )); do
        local physical_start=$((phys_first + rank * cores_per_rank + shift_amount))

        # Clamp to the compute physical range
        if [ "$physical_start" -gt "$phys_last_compute" ]; then
            physical_start=$phys_last_compute
        fi

        if [ "$cores_per_rank" -gt 1 ]; then
            local physical_end=$((physical_start + cores_per_rank - 1))
            if [ "$physical_end" -gt "$phys_last_compute" ]; then
                physical_end=$phys_last_compute
            fi

            if [ "$include_logical" -eq 1 ]; then
                local logical_start=$((physical_start + logical_offset))
                local logical_end=$((physical_end + logical_offset))
                cpu_ranges+="$physical_start-$physical_end,$logical_start-$logical_end:"
            else
                cpu_ranges+="$physical_start-$physical_end:"
            fi
        else
            if [ "$include_logical" -eq 1 ]; then
                local logical=$((physical_start + logical_offset))
                cpu_ranges+="$physical_start,$logical:"
            else
                cpu_ranges+="$physical_start:"
            fi
        fi
    done

    echo "${cpu_ranges%:}"
}

cpu_ranges_socket0=$(generate_cpu_ranges "$socket0_base" "$disabled_core_socket0" "$ranks_socket0" "$compute_physical_s0")
cpu_ranges_socket1=$(generate_cpu_ranges "$socket1_base" "$disabled_core_socket1" "$ranks_socket1" "$compute_physical_s1")

cpu_bind_list="${cpu_ranges_socket0}:${cpu_ranges_socket1}"

export CPU_BIND="list:$cpu_bind_list"
export CCL_WORKER_AFFINITY="$ccl_worker_affinity"
echo "CPU_BIND=list:$cpu_bind_list"
echo "CCL_WORKER_AFFINITY=$ccl_worker_affinity"

