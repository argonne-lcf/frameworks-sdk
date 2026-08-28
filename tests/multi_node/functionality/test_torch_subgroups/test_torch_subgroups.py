import os
import sys
import time

import torch
import torch.distributed as dist

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _common as C

MODE = os.environ.get("TEST_GROUPS", "ep")  # ep | pp | seq | disjoint | overlap

ctx = C.Ctx(f"subgroups/{MODE}")

# 2D mesh, EP within a row and PP down a column. EP must divide both the world and the
# ranks per node -- dividing only the world still straddles EP groups across nodes, which
# silently costs the locality the whole ep-vs-pp comparison rests on.
EP = int(os.environ.get("TEST_EP", "0")) or max(
    (d for d in range(1, min(6, ctx.world) + 1) if ctx.world % d == 0 and ctx.world // d >= 2),
    default=1)
RPN = C._envint("LOCAL_WORLD_SIZE", "PALS_LOCAL_SIZE", "OMPI_COMM_WORLD_LOCAL_SIZE", "MPI_LOCALNRANKS")
if ctx.world % EP:
    sys.exit(f"[fatal] TEST_EP={EP} does not divide world {ctx.world}")
if RPN and RPN % EP:
    sys.exit(f"[fatal] TEST_EP={EP} does not divide {RPN} ranks per node -- EP groups would straddle")
PP = ctx.world // EP

ep_mem = list(range(ctx.rank // EP * EP, ctx.rank // EP * EP + EP))
pp_mem = list(range(ctx.rank % EP, ctx.world, EP))

# new_group is collective over the whole world: every rank calls it for every group,
# including ones it never joins. Skipping those looks like an optimisation and hangs.
t0 = time.perf_counter()
ep_groups = [dist.new_group(list(range(g * EP, (g + 1) * EP))) for g in range(PP)]
t_ep = time.perf_counter() - t0
t0 = time.perf_counter()
pp_groups = [dist.new_group(list(range(c, ctx.world, EP))) for c in range(EP)]
t_pp = time.perf_counter() - t0

my_ep, my_pp = ep_groups[ctx.rank // EP], pp_groups[ctx.rank % EP]

# Off the largest group in play, so per-peer bytes match across modes and ep-vs-pp is a
# placement delta rather than a ring-length one.
GRP = ctx.world // 2 if MODE == "overlap" else max(EP, PP)
SETS = 2 if MODE in ("seq", "overlap") else 1
n = C.size_for(SETS * (GRP + 1))

gather = getattr(dist, "all_gather_single", None) or dist.all_gather_into_tensor  # renamed in 2.13


def gather_set(tag, group, members):
    # Keyed (tag, sender). A rank-only key would pass a message from the right rank on the
    # wrong communicator, which is the failure this test exists for -- see NEG=groups.
    src = torch.empty(n, dtype=C.DTYPE, device=ctx.device)
    out = torch.empty(n * len(members), dtype=C.DTYPE, device=ctx.device)
    C.fill(src, tag, ctx.rank)
    return (lambda: gather(out, src, group=group),
            lambda: C.check_finite(ctx, out) and C.check_regions(
                ctx, out, n, lambda i: (tag, members[i]), f"tag{tag} slot"),
            out.zero_)  # so a gather that no-ops cannot pass on the last iteration


report = None

if MODE == "pp":
    sets = [gather_set(1, my_pp, pp_mem)]
elif MODE == "seq":
    sets = [gather_set(0, my_ep, ep_mem), gather_set(1, my_pp, pp_mem)]
elif MODE == "overlap":
    # Two groups sharing a quarter of the world -- the case a partition cannot produce.
    half, q = ctx.world // 2, ctx.world // 4
    A, B = list(range(half)), list(range(q, q + half))
    ga, gb = dist.new_group(A), dist.new_group(B)
    sets = ([gather_set(2, ga, A)] if ctx.rank in A else []) + \
           ([gather_set(3, gb, B)] if ctx.rank in B else [])
    # Legal -- order is per communicator, not per rank -- but the shape a backend deadlocks
    # on if completion is serialised on the device. After bugs 1 and 5, a live suspect.
    if len(sets) == 2 and ctx.rank % 2:
        sets.reverse()
else:
    sets = [gather_set(0, my_ep, ep_mem)]

if MODE == "disjoint":
    # EP groups share no rank, so only the fabric can contend: one group alone against all
    # of them at once. Tails averaged because oneCCL settles in stages.
    fire = sets[0][0]

    def timed(active):
        ctx.barrier()
        t = time.perf_counter()
        if active:
            fire()
        ctx.sync()
        return time.perf_counter() - t

    CAL = int(os.environ.get("TEST_GROUP_CALIB", 8))
    solo = [timed(ctx.rank < EP) for _ in range(CAL)]  # rank 0 is in EP group 0, and log is rank 0
    conc = [timed(True) for _ in range(CAL)]
    t_solo, t_conc = sum(solo[-3:]) / 3, sum(conc[-3:]) / 3
    ctx.log("one group alone: " + " ".join(f"{t:.3f}" for t in solo))
    ctx.log("all groups conc: " + " ".join(f"{t:.3f}" for t in conc))
    report = lambda times: ctx.log(
        f"interference {t_conc / max(t_solo, 1e-9):.2f}x  ({PP} disjoint groups at once "
        f"{t_conc:.3f}s vs one alone {t_solo:.3f}s; 1.00 = the fabric absorbs them)")

ctx.log(f"mesh {EP}ep x {PP}pp  groups {PP} ep + {EP} pp  "
        f"created in {t_ep:.3f}s + {t_pp:.3f}s ({(t_ep + t_pp) / (EP + PP):.4f}s each)")
ctx.log(f"rank 0 ep={ep_mem} pp={pp_mem}  per-peer {C.human(n * torch.empty((), dtype=C.DTYPE).element_size())} "
        f"({n} elems) x {len(sets)} set(s)")

C.run(
    ctx,
    lambda: [f() for f, _, _ in sets],
    lambda: all(c() for _, c, _ in sets),
    lambda: [z() for _, _, z in sets],
    report,
)
