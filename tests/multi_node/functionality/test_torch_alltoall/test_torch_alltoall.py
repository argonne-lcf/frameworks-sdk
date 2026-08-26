import os
import sys

import torch
import torch.distributed as dist

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _common as C

ctx = C.Ctx("all_to_all_single")
n = C.size_for(2 * ctx.world)  # world chunks in, world chunks out
inp = torch.empty(n * ctx.world, dtype=C.DTYPE, device=ctx.device)
out = torch.empty(n * ctx.world, dtype=C.DTYPE, device=ctx.device)

# Keyed per (src, dst) so the receiver can prove chunk r really came from rank r.
for j in range(ctx.world):
    C.fill(inp[j * n : (j + 1) * n], ctx.rank, j)

ctx.log(f"per-peer {C.human(n * inp.element_size())} ({n} elems)  in/out {C.human(inp.nbytes)} each")

C.run(
    ctx,
    lambda: dist.all_to_all_single(out, inp),
    lambda: C.check_finite(ctx, out)
    and C.check_regions(ctx, out, n, lambda r: (r, ctx.rank), "chunk"),
)
