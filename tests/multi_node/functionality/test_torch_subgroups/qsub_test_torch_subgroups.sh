#!/bin/bash -x
#PBS -l select=64
#PBS -l place=scatter
#PBS -l walltime=00:20:00
#PBS -q workq
#PBS -A datascience
#PBS -l filesystems=home:tegu
#PBS -k doe
#PBS -j oe
#PBS -N ARDC_GRP

export TZ='/usr/share/zoneinfo/US/Central'

BENCH_DIR=${PBS_O_WORKDIR:-$(cd "$(dirname "$0")" && pwd)}
MACHINE=${MACHINE:-sunspot}   # sunspot | aurora

NNODES=$([ -n "${PBS_NODEFILE}" ] && wc -l < ${PBS_NODEFILE} || echo 1)
NRANKS_PER_NODE=${NRANKS_PER_NODE:-12}
export PALS_WORLD_SIZE=$((NNODES * NRANKS_PER_NODE))
echo "NNODES=${NNODES} PALS_WORLD_SIZE=${PALS_WORLD_SIZE}"

module add frameworks

export CCL_OP_SYNC=${CCL_OP_SYNC:-0}   # knob, not a default: the suite must run the configuration users actually run
export CCL_ATL_SYNC_COLL=${CCL_ATL_SYNC_COLL:-0}
export CCL_PROCESS_LAUNCHER=pmix
export CCL_ATL_TRANSPORT=mpi
export ZE_FLAT_DEVICE_HIERARCHY=FLAT
export FI_MR_CACHE_MONITOR=userfaultfd

export CCL_WORKER_AFFINITY="42,43,44,45,46,47,94,95,96,97,98,99"
export ZE_AFFINITY_MASK="0,1,2,3,4,5,6,7,8,9,10,11"
CPU_AFFINITY=$(bash ${BENCH_DIR}/../test_torch_overlap/get_cpu_bind_aurora.sh ${NRANKS_PER_NODE})

# Per-peer does NOT shrink with node count here -- groups stay the size of a mesh axis --
# so the budget sets it: B / (SETS * (max(EP,PP) + 1)), SETS = 2 in seq and overlap. At 6x4
# the default 50 is ~6.6 GiB per peer and past the 4 GiB cliff onto the scheduler path;
# 2.9 lands in bug 1's ~390 MiB window and stays on SYCL.
export TEST_MEM_BUDGET_GB=${TEST_MEM_BUDGET_GB:-50}
export TEST_ITERS=${TEST_ITERS:-10}
export TEST_DTYPE=${TEST_DTYPE:-bfloat16}
export TEST_TIMEOUT=${TEST_TIMEOUT:-600}

export TEST_GROUPS=${TEST_GROUPS:-ep}   # ep | pp | seq | disjoint | overlap

# Mesh split; EP must divide NRANKS_PER_NODE too. 0 auto-picks (6x4 at 24 ranks).
export TEST_EP=${TEST_EP:-0}

# The python resolves rank/world/local from PALS_* or torchrun's RANK/WORLD_SIZE,
# so both launchers work. mpiexec is the real path; torchrun is the single-node fallback.
if command -v mpiexec >/dev/null 2>&1 && [ -n "${PBS_NODEFILE}" ]; then
    mpiexec -n ${PALS_WORLD_SIZE} -ppn ${NRANKS_PER_NODE} -l --line-buffer ${CPU_AFFINITY} \
        -env MASTER_ADDR=$(hostname).hsn.cm.${MACHINE}.alcf.anl.gov \
        -env MASTER_PORT=2345 python ${BENCH_DIR}/test_torch_subgroups.py
else
    echo "no mpiexec / not under PBS -- torchrun fallback, SINGLE NODE ONLY (dev convenience)"
    torchrun --nproc_per_node=${NRANKS_PER_NODE} --master_port=2345 ${BENCH_DIR}/test_torch_subgroups.py
fi
