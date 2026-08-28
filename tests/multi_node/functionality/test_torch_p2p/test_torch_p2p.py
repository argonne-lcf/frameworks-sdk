import os
import sys

import torch
import torch.distributed as dist

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _common as C

MODE = os.environ.get("TEST_P2P", "ring")  # ring | ring_async | batch
STRIDE = int(os.environ.get("TEST_P2P_STRIDE", "1"))

ctx = C.Ctx(f"p2p/{MODE}")

# ring and ring_async are pipeline-parallel traffic: one message to the next stage, one
# from the previous. STRIDE places the neighbour -- 1 is adjacent, which on 2 nodes keeps
# all but two hops on Xe Link, so set it to the ranks per node to make every hop cross the
# fabric. batch posts world-1 sends and world-1 recvs in a single batch_isend_irecv: a
# hand-rolled alltoall carrying the same traffic as test_torch_alltoall through a
# different entry point, which is the axis every bug found so far has turned on.
if MODE == "batch":
    srcs = dsts = [r for r in range(ctx.world) if r != ctx.rank]
else:
    srcs = [(ctx.rank - STRIDE) % ctx.world]
    dsts = [(ctx.rank + STRIDE) % ctx.world]

n = C.size_for(len(srcs) + len(dsts))
inp = torch.empty(n * len(dsts), dtype=C.DTYPE, device=ctx.device)
out = torch.empty(n * len(srcs), dtype=C.DTYPE, device=ctx.device)

# Keyed per (src, dst) so the receiver can prove a message came from the rank it claims.
for i, d in enumerate(dsts):
    C.fill(inp[i * n : (i + 1) * n], ctx.rank, d)


def ring():
    # Send first only if this rank is the smaller end of its hop. Every cycle then holds
    # at least one rank that receives first, so unbuffered sends cannot deadlock -- for
    # any stride, including the one that degenerates the ring into disjoint pairs.
    if ctx.rank < dsts[0]:
        dist.send(inp, dsts[0])
        dist.recv(out, srcs[0])
    else:
        dist.recv(out, srcs[0])
        dist.send(inp, dsts[0])


def ring_async():
    for r in [dist.irecv(out, srcs[0]), dist.isend(inp, dsts[0])]:
        r.wait()


def batch():
    ops = [dist.P2POp(dist.irecv, out[i * n : (i + 1) * n], s) for i, s in enumerate(srcs)]
    ops += [dist.P2POp(dist.isend, inp[i * n : (i + 1) * n], d) for i, d in enumerate(dsts)]
    for r in dist.batch_isend_irecv(ops):
        r.wait()


ctx.log(f"{MODE} stride={STRIDE} peers={len(dsts)}  "
        f"per-message {C.human(n * inp.element_size())} ({n} elems)  "
        f"in {C.human(inp.nbytes)}  out {C.human(out.nbytes)}")

C.run(
    ctx,
    {"ring": ring, "ring_async": ring_async, "batch": batch}[MODE],
    lambda: C.check_finite(ctx, out)
    and C.check_regions(ctx, out, n, lambda i: (srcs[i], ctx.rank), "message"),
    out.zero_,  # a recv that silently does nothing must not pass on the previous iteration
)
