"""Fault injection to prove the validators actually fail. A silently-passing check is
the worst outcome at 120k ranks, so this corrupts one rank and asserts the whole job
goes red. Not a platform test -- run it after touching _common.py.

  NEG=misroute|nan|scale|offset|p2p TEST_DEVICE=cpu TEST_MEM_BUDGET_GB=0.02 TEST_ITERS=1 \
      TEST_CHUNK=4096 torchrun --nproc_per_node=4 _negtest.py   # must exit 1 everywhere

A small TEST_CHUNK is what makes these bite: it forces buffers across many RNG chunks
at smoke-test sizes, so the chunk-straddling arithmetic is actually exercised.
"""

import os
import sys

import torch
import torch.distributed as dist

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _common as C

MODE = os.environ.get("NEG", "misroute")
ctx = C.Ctx("neg/" + MODE)

if MODE == "scale":
    n = C.size_for(1)
    buf = torch.empty(n, dtype=C.DTYPE, device=ctx.device)
    mine, total = C.scalars(ctx)
    C.run(ctx, lambda: dist.all_reduce(buf),
          lambda: C.check_finite(ctx, buf) and C.check_scaled(ctx, buf, total * 1.5, 0),
          lambda: (C.fill(buf, 0), buf.mul_(mine)))
elif MODE == "offset":
    # Check each reduce_scatter shard against its neighbour's slice. Must fail -- that is
    # what proves check_scaled's offset picks a real region, not an empty or wrong one.
    n = C.size_for(ctx.world + 1)
    inp = torch.empty(n * ctx.world, dtype=C.DTYPE, device=ctx.device)
    out = torch.empty(n, dtype=C.DTYPE, device=ctx.device)
    mine, total = C.scalars(ctx)
    scatter = getattr(dist, "reduce_scatter_single", None) or dist.reduce_scatter_tensor
    C.run(ctx, lambda: scatter(out, inp),
          lambda: C.check_scaled(ctx, out, total, 0, whole=n * ctx.world,
                                 offset=((ctx.rank + 1) % ctx.world) * n),
          lambda: (C.fill(inp, 0), inp.mul_(mine)))
elif MODE == "p2p":
    # One received message, so check_regions sees a buffer with fewer regions than ranks.
    # Must fail -- that is what proves the region count it derives is not zero, i.e. that
    # the p2p check looks at something instead of passing vacuously.
    n = C.size_for(2)
    prv, nxt = (ctx.rank - 1) % ctx.world, (ctx.rank + 1) % ctx.world
    inp = torch.empty(n, dtype=C.DTYPE, device=ctx.device)
    out = torch.empty(n, dtype=C.DTYPE, device=ctx.device)
    C.fill(inp, ctx.rank, nxt)

    def op():
        order = [lambda: dist.send(inp, nxt), lambda: dist.recv(out, prv)]
        for f in order if ctx.rank < nxt else order[::-1]:
            f()
        if ctx.rank == 1:
            out[7] += 1.0

    C.run(ctx, op, lambda: C.check_regions(ctx, out, n, lambda i: (prv, ctx.rank), "message"))
else:
    n = C.size_for(2 * ctx.world)
    inp = torch.empty(n * ctx.world, dtype=C.DTYPE, device=ctx.device)
    out = torch.empty(n * ctx.world, dtype=C.DTYPE, device=ctx.device)
    for j in range(ctx.world):
        C.fill(inp[j * n : (j + 1) * n], ctx.rank, j)

    def op():
        dist.all_to_all_single(out, inp)
        if ctx.rank == 1:  # exactly one rank goes bad
            out[n + 7] = float("nan") if MODE == "nan" else out[n + 7] + 1.0

    C.run(ctx, op, lambda: C.check_finite(ctx, out)
          and C.check_regions(ctx, out, n, lambda r: (r, ctx.rank), "chunk"))
