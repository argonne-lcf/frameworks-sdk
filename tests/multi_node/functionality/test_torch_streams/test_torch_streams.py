import os
import sys
import time

import torch
import torch.distributed as dist

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _common as C

# Can this device overlap two independent streams AT ALL? No collectives here on purpose:
# this is the layer underneath them. Every comm/compute overlap result is conditional on
# this one, because if two plain gemms on separate streams serialise then nothing above the
# driver can overlap either -- and swapping oneCCL for another comm library cannot help.
ctx = C.Ctx("streams")

if ctx.device.type == "cpu":
    ctx.log("no accelerator streams on cpu -- nothing to measure")
    ctx.barrier()  # rank 0 leaving early tears the store down under ranks still in init
    dist.destroy_process_group()
    sys.exit(0)
if not hasattr(torch.accelerator, "set_stream"):
    sys.exit("[fatal] torch.accelerator.set_stream missing -- need a newer torch")

M = int(os.environ.get("TEST_GEMM_M", 8192))
a = torch.empty((M, M), dtype=C.DTYPE, device=ctx.device).normal_()
b = torch.empty((M, M), dtype=C.DTYPE, device=ctx.device).normal_()
ca = torch.empty((M, M), dtype=C.DTYPE, device=ctx.device)
cb = torch.empty((M, M), dtype=C.DTYPE, device=ctx.device)  # own output per stream, so the
                                                            # two never share a dependency
n = int(float(os.environ.get("TEST_COPY_GB", 4)) * 1e9) // 2
src = torch.empty(n, dtype=C.DTYPE, device=ctx.device)
dst = torch.empty(n, dtype=C.DTYPE, device=ctx.device)

sa, sb = torch.Stream(device=ctx.device), torch.Stream(device=ctx.device)


def gemm(out, reps):
    for _ in range(reps):
        torch.mm(a, b, out=out)


def copy(reps):
    for _ in range(reps):
        dst.copy_(src)


def timed(fn):
    torch.accelerator.synchronize()
    t = time.perf_counter()
    fn()
    torch.accelerator.synchronize()
    return time.perf_counter() - t


def solo(s, f):
    torch.accelerator.set_stream(s)
    return timed(f)


def together(fa, fb):
    def go():
        torch.accelerator.set_stream(sa)
        fa()
        torch.accelerator.set_stream(sb)
        fb()  # enqueued while A is still running; the device decides whether they share
    return timed(go)


def measure(label, fa, fb):
    solo(sa, fa), solo(sb, fb)  # warm up: same first-call rule as everywhere else here
    # min of 3, not mean: for a yes/no concurrency question the best case is the honest
    # one, since noise can only push the two apart and never fake an overlap.
    ta = min(solo(sa, fa) for _ in range(3))
    tb = min(solo(sb, fb) for _ in range(3))
    tboth = min(together(fa, fb) for _ in range(3))
    score = (ta + tb - tboth) / min(ta, tb)
    ctx.log(f"{label}  A {ta:.3f}s  B {tb:.3f}s  serial {ta + tb:.3f}s  "
            f"together {tboth:.3f}s  overlap {score:.2f}")
    return score


# Match the copy to the gemm so neither hides trivially inside the other.
reps = max(1, int(os.environ.get("TEST_GEMM_REPS", 20)))
t1 = solo(sa, lambda: gemm(ca, reps))
creps = max(1, round(t1 / max(solo(sb, lambda: copy(1)), 1e-6)))
ctx.log(f"gemm {M}^3 x{reps} = {t1:.3f}s   copy {C.human(src.nbytes)} x{creps}")

g = measure("gemm || gemm", lambda: gemm(ca, reps), lambda: gemm(cb, reps))
h = measure("gemm || copy", lambda: gemm(ca, reps), lambda: copy(creps))

ctx.log("=> " + (
    "device does NOT overlap independent streams -- bug 4 is below the comm stack "
    "entirely, and no comm library can fix it" if g < 0.15 and h < 0.15 else
    "copy engines overlap with compute but compute kernels do not -- oneCCL moving data "
    "with compute kernels would fully explain bug 4" if g < 0.15 else
    "device overlaps independent streams fine -- the serialisation really is in the "
    "comm stack, so torchcomms is worth trying"))
ctx.log("RESULT PASS")  # diagnostic: the scores are the output, there is nothing to fail
dist.destroy_process_group()
