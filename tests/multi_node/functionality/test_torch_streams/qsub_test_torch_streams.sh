#!/bin/bash -x
#PBS -l select=1
#PBS -l place=scatter
#PBS -l walltime=00:15:00
#PBS -q workq
#PBS -A datascience
#PBS -l filesystems=home:tegu
#PBS -k doe
#PBS -j oe
#PBS -N ARDC_STRM

export TZ='/usr/share/zoneinfo/US/Central'

BENCH_DIR=${PBS_O_WORKDIR:-$(cd "$(dirname "$0")" && pwd)}
MACHINE=${MACHINE:-sunspot}

# Single rank by default: this is a local device question, not a fabric one, and one rank
# per tile gives the cleanest signal. Raise NRANKS_PER_NODE to ask the same question under
# the contention a real job creates.
NNODES=$([ -n "${PBS_NODEFILE}" ] && wc -l < ${PBS_NODEFILE} || echo 1)
NRANKS_PER_NODE=${NRANKS_PER_NODE:-1}
export PALS_WORLD_SIZE=$((NNODES * NRANKS_PER_NODE))
echo "NNODES=${NNODES} PALS_WORLD_SIZE=${PALS_WORLD_SIZE}"

module add frameworks

export CCL_PROCESS_LAUNCHER=pmix
export CCL_ATL_TRANSPORT=mpi
export ZE_FLAT_DEVICE_HIERARCHY=FLAT
export FI_MR_CACHE_MONITOR=userfaultfd

export CCL_WORKER_AFFINITY="42,43,44,45,46,47,94,95,96,97,98,99"
export ZE_AFFINITY_MASK="0,1,2,3,4,5,6,7,8,9,10,11"
CPU_AFFINITY=$(bash ${BENCH_DIR}/../test_torch_overlap/get_cpu_bind_aurora.sh ${NRANKS_PER_NODE})

export TEST_GEMM_M=${TEST_GEMM_M:-8192}
export TEST_GEMM_REPS=${TEST_GEMM_REPS:-20}
export TEST_COPY_GB=${TEST_COPY_GB:-4}
export TEST_DTYPE=${TEST_DTYPE:-bfloat16}
export TEST_TIMEOUT=${TEST_TIMEOUT:-600}

if command -v mpiexec >/dev/null 2>&1 && [ -n "${PBS_NODEFILE}" ]; then
    mpiexec -n ${PALS_WORLD_SIZE} -ppn ${NRANKS_PER_NODE} -l --line-buffer ${CPU_AFFINITY} \
        -env MASTER_ADDR=$(hostname).hsn.cm.${MACHINE}.alcf.anl.gov \
        -env MASTER_PORT=2345 python ${BENCH_DIR}/test_torch_streams.py
else
    echo "no mpiexec / not under PBS -- torchrun fallback, SINGLE NODE ONLY (dev convenience)"
    torchrun --nproc_per_node=${NRANKS_PER_NODE} --master_port=2345 ${BENCH_DIR}/test_torch_streams.py
fi
