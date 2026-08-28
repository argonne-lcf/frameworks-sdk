import os
import sys
import time

import torch
import torch.distributed as dist

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _common as C

COLL = os.environ.get("TEST_OVERLAP_COLL", "all_reduce")  # all_reduce | all_gather | p2p

ctx = C.Ctx(f"overlap_{COLL}")

# all_reduce is the one collective bug 1 does not touch at any reachable size, so this
# runs at full budget with CCL_OP_SYNC=0 and the async path intact -- which is the whole
# point: forcing synchronous completion would defeat an overlap test.
#
# all_gather is the control. ProcessGroupXCCL's async path is correctly plumbed (separate
# stream when asyncOp, event-ordered against the compute stream, stream-blocking wait), so
# a zero overlap score cannot be an API defect -- it is either the reduction kernels
# competing with the gemm for Xe cores, or a serializing submission below PyTorch.
# all_gather is pure data movement with no reduction kernels, which separates the two.
#
# p2p is the empty cell in the bug 4 grid, and the reason this branch exists: every overlap
# number so far is either a collective against compute (0.01-0.14) or P2P against other P2P
# (0.96). Network P2P against compute has never been measured, and it is the cell a pipeline
# schedule stands on -- whether a stage can hide its activation exchange behind the next
# micro-batch, i.e. whether DualPipe's F&B term is real on this stack or collapses to F+B.
#
# Each branch also supplies `reset` and `check` so prep and validate stay one line each.
if COLL == "all_gather":
    n = C.size_for(ctx.world + 1)
    src = torch.empty(n, dtype=C.DTYPE, device=ctx.device)
    buf = torch.empty(n * ctx.world, dtype=C.DTYPE, device=ctx.device)
    # Renamed in torch 2.13; Sunspot's frameworks module may predate that.
    gather = getattr(dist, "all_gather_single", None) or dist.all_gather_into_tensor
    coll = lambda **kw: gather(buf, src, **kw)
    reset = lambda: (C.fill(src, ctx.rank), buf.zero_())
    check = lambda: C.check_regions(ctx, buf, n, lambda r: (r,), "shard")
elif COLL == "p2p":
    class _Batch:
        """batch_isend_irecv hands back a list of Works where a collective hands back one.
        Wrapping it keeps the async_op=True / blocking split identical for both."""

        def __init__(self, reqs, async_op=False):
            self.reqs = reqs
            if not async_op:
                self.wait()

        def wait(self):
            for r in self.reqs:
                r.wait()

    # batch_isend_irecv is the one bidirectional idiom that does not deadlock here (bug 5),
    # and it is the transport a pipeline stage would actually use. STRIDE has to put the peer
    # off-node: at stride 1 this measures Xe Link, which is local copy against compute, and
    # that cell is already filled.
    stride = int(os.environ.get("TEST_P2P_STRIDE", "1"))
    prv, nxt = (ctx.rank - stride) % ctx.world, (ctx.rank + stride) % ctx.world
    n = C.size_for(2)
    src = torch.empty(n, dtype=C.DTYPE, device=ctx.device)
    buf = torch.empty(n, dtype=C.DTYPE, device=ctx.device)
    C.fill(src, ctx.rank, nxt)
    coll = lambda **kw: _Batch(dist.batch_isend_irecv(
        [dist.P2POp(dist.irecv, buf, prv), dist.P2POp(dist.isend, src, nxt)]), **kw)
    reset = buf.zero_  # a recv that silently does nothing must not pass on the last iteration
    check = lambda: C.check_regions(ctx, buf, n, lambda i: (prv, ctx.rank), "message")
    ctx.log(f"p2p stride={stride}  rank 0 hop {prv} -> {ctx.rank} -> {nxt}")
else:
    n = C.size_for(1)
    buf = torch.empty(n, dtype=C.DTYPE, device=ctx.device)
    mine, total = C.scalars(ctx)
    coll = lambda **kw: dist.all_reduce(buf, **kw)
    reset = lambda: (C.fill(buf, 0), buf.mul_(mine))
    check = lambda: C.check_scaled(ctx, buf, total, 0)

# Compute length is set by the repeat count, not the matrix size, so the operands stay
# small next to the comm buffer. Default is small on CPU or run_local takes minutes.
M = int(os.environ.get("TEST_GEMM_M", 1024 if ctx.device.type == "cpu" else 8192))
a = torch.empty((M, M), dtype=C.DTYPE, device=ctx.device).normal_()
b = torch.empty((M, M), dtype=C.DTYPE, device=ctx.device).normal_()
c = torch.empty((M, M), dtype=C.DTYPE, device=ctx.device)


def prep():
    reset()
    c.zero_()  # so the gemm check catches compute that never ran, not just wrong results


def gemm(reps):
    for _ in range(reps):
        torch.mm(a, b, out=c)


def timed(fn):
    prep()
    ctx.barrier()  # its trailing sync() drains prep, so only fn is timed
    t = time.perf_counter()
    fn()
    ctx.sync()
    return time.perf_counter() - t


# Solo baselines. Without both of them the overlapped time means nothing -- and the comm
# baseline has to reach steady state first, which takes more than dropping call 1. On a
# fresh buffer call 1 pays fabric registration and oneCCL scratch allocation (20.614s at
# 18.63GiB on Sunspot, against ~1.4s after); a single-shot baseline inflated 14x that way
# scores 0.93 overlap on a run that overlapped nothing. But settling continues past call 1:
# all_reduce@18.63GiB stepped again near call 11, and a baseline taken from calls 2-3 would
# credit that speedup to overlap. So profile until it flattens and take the tail -- and log
# the whole profile, because the shape of the settling is itself the diagnostic.
CALIB = int(os.environ.get("TEST_COMM_CALIB", 12))
solo = [timed(coll) for _ in range(CALIB)]
t_first, t_comm = solo[0], sum(solo[-3:]) / 3
ctx.log("comm solo: " + " ".join(f"{t:.3f}" for t in solo))
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

ctx.log(f"{COLL}  buffer {C.human(buf.nbytes)} ({buf.numel()} elems)  gemm {M}^3 x{reps}  "
        f"comm {t_comm:.3f}s (first call {t_first:.3f}s)  compute {t_gemm:.3f}s solo")


def op():
    w = coll(async_op=True)
    gemm(reps)
    w.wait()


def validate():
    ok = C.check_finite(ctx, buf) and check()
    if not torch.equal(c, ref):
        ctx.fail("gemm output differs from its solo reference")
        return False
    ctx.log("gemm bitwise identical to solo reference")
    return ok


def report(times):
    both = sum(times[1:]) / max(1, len(times) - 1)
    serial = t_comm + t_gemm
    # 1 = compute fully hidden behind comm, 0 = fully serialized, <0 = the two contend.
    # "comm exposed" is the same result stated so it cannot be misread: how much of the
    # collective you still pay for after the compute is accounted for.
    ctx.log(f"overlap {(serial - both) / min(t_comm, t_gemm):.2f}  "
            f"(overlapped {both:.3f}s vs serial {serial:.3f}s; "
            f"comm exposed {both - t_gemm:.3f}s of {t_comm:.3f}s)")


C.run(ctx, op, validate, prep, report)
