import os
import sys
import time

import torch
import torch.distributed as dist

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _common as C

ctx = C.Ctx("overlap_all_reduce")

# all_reduce is the one collective bug 1 does not touch at any reachable size, so this
# runs at full budget with CCL_OP_SYNC=0 and the async path intact -- which is the whole
# point: forcing synchronous completion would defeat an overlap test.
n = C.size_for(1)
buf = torch.empty(n, dtype=C.DTYPE, device=ctx.device)
mine, total = C.scalars(ctx)

# Compute length is set by the repeat count, not the matrix size, so the operands stay
# small next to the comm buffer. Default is small on CPU or run_local takes minutes.
M = int(os.environ.get("TEST_GEMM_M", 1024 if ctx.device.type == "cpu" else 8192))
a = torch.empty((M, M), dtype=C.DTYPE, device=ctx.device).normal_()
b = torch.empty((M, M), dtype=C.DTYPE, device=ctx.device).normal_()
c = torch.empty((M, M), dtype=C.DTYPE, device=ctx.device)


def prep():
    C.fill(buf, 0)
    buf.mul_(mine)
    c.zero_()  # so the gemm check catches compute that never ran, not just wrong results


def gemm(reps):
    for _ in range(reps):
        torch.mm(a, b, out=c)


def timed(fn):
    ctx.barrier()  # its trailing sync() drains prep, so only fn is timed
    t = time.perf_counter()
    fn()
    ctx.sync()
    return time.perf_counter() - t


# Solo baselines. Without both of them the overlapped time means nothing.
prep()
t_comm = timed(lambda: dist.all_reduce(buf))
gemm(1)  # warm up XMX / autotune before the calibration measurement
ctx.sync()
# Rough is fine -- reps only has to make compute comparable to comm; t_gemm is measured.
reps = max(1, min(round(t_comm / timed(lambda: gemm(1))), 100000))

# Every rank must do the same amount of compute, or the slowest one sets the overlapped
# time and the comparison measures rank skew instead of overlap.
r = torch.tensor([reps], device=ctx.device)
dist.all_reduce(r, op=dist.ReduceOp.MAX)
reps = int(r.item())
t_gemm = timed(lambda: gemm(reps))
ref = c.clone()

ctx.log(f"buffer {C.human(buf.nbytes)} ({n} elems)  gemm {M}^3 x{reps}  "
        f"comm {t_comm:.3f}s  compute {t_gemm:.3f}s solo")


def op():
    w = dist.all_reduce(buf, async_op=True)
    gemm(reps)
    w.wait()


def validate():
    ok = C.check_finite(ctx, buf) and C.check_scaled(ctx, buf, total, 0)
    if not torch.equal(c, ref):
        ctx.fail("gemm output differs from its solo reference")
        return False
    ctx.log("gemm bitwise identical to solo reference")
    return ok


def report(times):
    both = sum(times[1:]) / max(1, len(times) - 1)
    serial = t_comm + t_gemm
    # 1 = compute fully hidden behind comm, 0 = fully serialized, <0 = the two contend
    ctx.log(f"overlap {(serial - both) / min(t_comm, t_gemm):.2f}  "
            f"(overlapped {both:.3f}s vs serial {serial:.3f}s)")


C.run(ctx, op, validate, prep, report)
