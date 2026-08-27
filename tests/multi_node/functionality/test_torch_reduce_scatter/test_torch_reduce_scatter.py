import os
import sys

import torch
import torch.distributed as dist

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _common as C

ctx = C.Ctx("reduce_scatter_tensor")
n = C.size_for(ctx.world + 1)  # world input regions plus the local output shard
inp = torch.empty(n * ctx.world, dtype=C.DTYPE, device=ctx.device)
out = torch.empty(n, dtype=C.DTYPE, device=ctx.device)

# Same closed form as all_reduce -- shared random base, per-rank scalar -- but each rank
# keeps only its own slice of the sum, so the reference is base[rank*n:(rank+1)*n] * total.
mine, total = C.scalars(ctx)

ctx.log(f"input {C.human(inp.nbytes)}  shard {C.human(out.nbytes)} ({n} elems)")

# Renamed in torch 2.13; Sunspot's frameworks module may predate that.
scatter = getattr(dist, "reduce_scatter_single", None) or dist.reduce_scatter_tensor


def prep():
    C.fill(inp, 0)
    inp.mul_(mine)


C.run(
    ctx,
    lambda: scatter(out, inp),
    lambda: C.check_finite(ctx, out)
    and C.check_scaled(ctx, out, total, 0, whole=n * ctx.world, offset=ctx.rank * n),
    prep,
)
