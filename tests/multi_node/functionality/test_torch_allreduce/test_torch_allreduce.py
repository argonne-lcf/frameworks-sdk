import os
import sys

import torch
import torch.distributed as dist

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _common as C

ctx = C.Ctx("all_reduce")
n = C.size_for(1)
buf = torch.empty(n, dtype=C.DTYPE, device=ctx.device)

# Every rank holds the same random `base` scaled by its own positive scalar, so the
# sum has the closed form base * total and can be checked at O(N) at any world size.
mine, total = C.scalars(ctx)

ctx.log(f"buffer {C.human(buf.nbytes)} ({n} elems) in place")


def prep():
    C.fill(buf, 0)
    buf.mul_(mine)


C.run(
    ctx,
    lambda: dist.all_reduce(buf),
    lambda: C.check_finite(ctx, buf) and C.check_scaled(ctx, buf, total, 0),
    prep,
)
