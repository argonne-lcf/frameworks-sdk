"""Fault injection to prove the validators actually fail. A silently-passing check is
the worst outcome at 120k ranks, so this corrupts one rank and asserts the whole job
goes red. Not a platform test -- run it after touching _common.py.

  NEG=misroute|nan|scale TEST_DEVICE=cpu TEST_MEM_BUDGET_GB=0.02 TEST_ITERS=1 \
      torchrun --nproc_per_node=4 _negtest.py     # must exit 1 on every rank
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
    a = torch.empty(ctx.world, dtype=torch.float64).uniform_(
        0.5, 1.5, generator=torch.Generator().manual_seed(C.SEED))
    mine, total = a[ctx.rank].item(), a.sum().item()
    C.run(ctx, lambda: dist.all_reduce(buf),
          lambda: C.check_finite(ctx, buf) and C.check_scaled(ctx, buf, total * 1.5, 0),
          lambda: (C.fill(buf, 0), buf.mul_(mine)))
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
