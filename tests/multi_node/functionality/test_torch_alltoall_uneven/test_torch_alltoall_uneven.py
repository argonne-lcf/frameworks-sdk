import os
import sys

import torch
import torch.distributed as dist

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _common as C

COLS = 1024  # all_to_all_single splits along dim 0, so the payload unit is a row
SKEW = os.environ.get("TEST_SKEW", "skew")  # skew | incast
HOT = int(os.environ.get("TEST_HOT", "8"))


def weight(src, dst):
    """Relative rows sent src->dst. `skew` mimics top-k routing imbalance with balanced
    per-rank totals; `incast` funnels HOT times the traffic into rank 0."""
    if SKEW == "incast":
        return HOT if dst == 0 else 1
    return 1 + ((src + dst) % 4)


ctx = C.Ctx(f"all_to_all_single uneven/{SKEW}")
w_out = [weight(ctx.rank, j) for j in range(ctx.world)]
w_in = [weight(j, ctx.rank) for j in range(ctx.world)]

# Size from the busiest rank, not this one: under incast rank 0 dwarfs everyone else.
d = torch.tensor([sum(w_out) + sum(w_in)], device=ctx.device)
dist.all_reduce(d, op=dist.ReduceOp.MAX)
u = max(1, int(C.BUDGET // (d.item() * COLS * torch.empty((), dtype=C.DTYPE).element_size())))

in_splits = [u * w for w in w_out]
out_splits = [u * w for w in w_in]
inp = torch.empty(sum(in_splits) * COLS, dtype=C.DTYPE, device=ctx.device)
out = torch.empty(sum(out_splits) * COLS, dtype=C.DTYPE, device=ctx.device)

o = 0
for j, s in enumerate(in_splits):
    C.fill(inp[o : o + s * COLS], ctx.rank, j)
    o += s * COLS

ctx.log(f"unit {u} rows x {COLS}  in {C.human(inp.nbytes)}  out {C.human(out.nbytes)}")

C.run(
    ctx,
    lambda: dist.all_to_all_single(out.view(-1, COLS), inp.view(-1, COLS), out_splits, in_splits),
    lambda: C.check_finite(ctx, out)
    and C.check_regions(ctx, out, [s * COLS for s in out_splits], lambda r: (r, ctx.rank), "chunk"),
)
