import os
import sys

import torch
import torch.distributed as dist

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _common as C

ctx = C.Ctx("all_gather_into_tensor")
n = C.size_for(ctx.world + 1)  # world output regions plus the local shard
src = torch.empty(n, dtype=C.DTYPE, device=ctx.device)
out = torch.empty(n * ctx.world, dtype=C.DTYPE, device=ctx.device)
C.fill(src, ctx.rank)

ctx.log(f"shard {C.human(src.nbytes)} ({n} elems)  gathered {C.human(out.nbytes)}")

# Renamed in torch 2.13; Sunspot's frameworks module may predate that.
gather = getattr(dist, "all_gather_single", None) or dist.all_gather_into_tensor

C.run(
    ctx,
    lambda: gather(out, src),
    lambda: C.check_finite(ctx, out) and C.check_regions(ctx, out, n, lambda r: (r,), "shard"),
)
