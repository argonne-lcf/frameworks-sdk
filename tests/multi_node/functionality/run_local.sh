#!/bin/bash
# Local CPU/gloo smoke test -- proves the harness before it reaches Sunspot.
# SINGLE NODE ONLY, purely a development convenience. The real launch path is
# mpiexec + PALS via the per-test qsub scripts.
#
#   ./run_local.sh        the four collectives via torchrun; every case must PASS
#   ./run_local.sh pals   same, but resolving rank/world from PALS_* only (as mpiexec
#                         does) with RANK/WORLD_SIZE/LOCAL_RANK unset
#   ./run_local.sh neg    fault injection; every case must be DETECTED
#
# Override: TORCHRUN, PYTHON, NP, TEST_MEM_BUDGET_GB, TEST_ITERS, TEST_DTYPE
set -u
cd "$(dirname "$0")"

TORCHRUN=${TORCHRUN:-torchrun}
PYTHON=${PYTHON:-python}
NP=${NP:-4}
PORT=${PORT:-29580}
TESTS="allreduce allgather alltoall alltoall_uneven reduce_scatter"
export TEST_DEVICE=cpu
export TEST_MEM_BUDGET_GB=${TEST_MEM_BUDGET_GB:-0.02}
export TEST_ITERS=${TEST_ITERS:-3}
rc=0

case "${1:-run}" in
neg)
    # Small chunks so smoke-test buffers still straddle RNG chunk boundaries.
    for m in misroute nan scale offset; do
        if NEG=$m TEST_CHUNK=${TEST_CHUNK:-4096} \
                $TORCHRUN --nproc_per_node=$NP --master_port=$PORT _negtest.py \
                >/tmp/neg_$m.log 2>&1; then
            echo "BAD   $m NOT detected -- the validator is not doing its job"; rc=1
        else
            echo "ok    $m detected"
        fi
    done
    ;;
pals)
    export MASTER_ADDR=127.0.0.1 MASTER_PORT=$PORT
    for t in $TESTS; do
        pids=""
        for r in $(seq 0 $((NP - 1))); do
            ( cd test_torch_$t && env -u RANK -u WORLD_SIZE -u LOCAL_RANK \
                PALS_RANKID=$r PALS_WORLD_SIZE=$NP PALS_LOCAL_RANKID=$r PALS_LOCAL_SIZE=$NP \
                $PYTHON test_torch_$t.py >/tmp/pals_${t}_$r.log 2>&1 ) &
            pids="$pids $!"
        done
        bad=0
        for p in $pids; do wait $p || bad=1; done
        if [ $bad -eq 0 ]; then
            echo "ok    $t   $(grep -h 'local check' /tmp/pals_${t}_0.log | head -1)"
        else
            echo "FAIL  $t   see /tmp/pals_${t}_*.log"; rc=1
        fi
    done
    ;;
*)
    for t in $TESTS; do
        if ( cd test_torch_$t && $TORCHRUN --nproc_per_node=$NP --master_port=$PORT \
                test_torch_$t.py >/tmp/run_$t.log 2>&1 ); then
            echo "ok    $t   $(grep -h 'local check' /tmp/run_$t.log | head -1)"
        else
            echo "FAIL  $t   see /tmp/run_$t.log"; rc=1
        fi
    done
    ;;
esac

[ $rc -eq 0 ] && echo "ALL OK" || echo "FAILURES"
exit $rc
