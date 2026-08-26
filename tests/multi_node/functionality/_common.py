"""Shared harness for the multi-node communication tests.

Payload size is derived from the world size so the same file runs from one node
to ~10k nodes without OOM. References for validation are O(N) and independent of
world size: buffers are generated in fixed-size chunks with per-chunk seeds, so
any chunk can be regenerated without generating everything before it.
"""

import contextlib
import datetime
import os
import sys
import threading
import time

import torch
import torch.distributed as dist

SEED = 1234
CHUNK = 1 << 26  # elements per RNG chunk
ALIGN = 512  # element alignment for message sizes
BUDGET = int(float(os.environ.get("TEST_MEM_BUDGET_GB", "50")) * 1e9)
ITERS = int(os.environ.get("TEST_ITERS", "10"))
TIMEOUT = int(os.environ.get("TEST_TIMEOUT", "600"))
NCHECK = int(os.environ.get("TEST_NCHECK", "32"))
DTYPE = getattr(torch, os.environ.get("TEST_DTYPE", "bfloat16"))
# Tolerance assumes the backend accumulates in fp32, whose error does not grow with
# world size. Accumulating bf16 in bf16 stagnates instead (terms below half an ULP of
# the running sum vanish, error -> 1.0 past a few thousand ranks), so exceeding this
# is a real finding about the backend rather than noise. TEST_RTOL overrides.
RTOL = float(os.environ.get("TEST_RTOL", 0)) or {torch.bfloat16: 0.05, torch.float16: 0.01}.get(DTYPE, 1e-4)


def _envint(*names):
    for n in names:
        if os.environ.get(n) is not None:
            return int(os.environ[n])
    return None


_GENS = {}


def _gen(device, *key):
    """Reseeded, not reconstructed: all_to_all seeds once per peer, 120k times at full scale."""
    h = SEED
    for v in key:
        h = (h * 1000003 + int(v) + 0x9E3779B9) & 0x7FFFFFFF
    g = _GENS.get(str(device))
    if g is None:
        g = _GENS[str(device)] = torch.Generator(device=device)
    return g.manual_seed(h)


def fill(buf, *key):
    """Fill buf with deterministic pseudo-random data, chunk-addressable by key. Keys are ints."""
    n = buf.numel()
    for i in range(0, n, CHUNK):
        buf[i : i + min(CHUNK, n - i)].normal_(generator=_gen(buf.device, *key, i // CHUNK))


def chunk(total, j, dtype, device, *key):
    """Regenerate chunk j of a buffer of `total` elements built by fill(..., *key)."""
    m = min(CHUNK, total - j * CHUNK)
    return torch.empty(m, dtype=dtype, device=device).normal_(generator=_gen(device, *key, j))


def nchunks(total):
    return (total + CHUNK - 1) // CHUNK


def size_for(parts, dtype=DTYPE):
    """Largest aligned per-part element count fitting `parts` of them in BUDGET."""
    n = BUDGET // (parts * torch.empty((), dtype=dtype).element_size())
    return max(ALIGN, (n // ALIGN) * ALIGN)


def human(nbytes):
    for u in ("B", "KiB", "MiB", "GiB"):
        if nbytes < 1024 or u == "GiB":
            return f"{nbytes:.2f}{u}"
        nbytes /= 1024


class Ctx:
    def __init__(self, prim):
        self.prim = prim
        self.failed = False
        self.rank = _envint("RANK", "PALS_RANKID", "PMIX_RANK", "OMPI_COMM_WORLD_RANK", "PMI_RANK", "SLURM_PROCID")
        self.world = _envint("WORLD_SIZE", "PALS_WORLD_SIZE", "PALS_NRANKS", "OMPI_COMM_WORLD_SIZE", "PMI_SIZE", "SLURM_NTASKS")
        if self.rank is None or self.world is None:
            sys.exit("[fatal] cannot resolve RANK / WORLD_SIZE from environment")

        acc = torch.accelerator.current_accelerator() if torch.accelerator.is_available() else None
        if os.environ.get("TEST_DEVICE") == "cpu" or acc is None:
            self.device, backend = torch.device("cpu"), "gloo"
        else:
            ndev = torch.accelerator.device_count()
            local = _envint("LOCAL_RANK", "PALS_LOCAL_RANKID", "MPI_LOCALRANKID",
                            "OMPI_COMM_WORLD_LOCAL_RANK", "PMI_LOCAL_RANK", "SLURM_LOCALID")
            local = self.rank % max(1, ndev) if local is None else local
            torch.accelerator.set_device_index(local)
            self.device = torch.device(acc.type, local)
            backend = dist.get_default_backend_for_device(acc.type)

        os.environ.setdefault("MASTER_ADDR", "127.0.0.1")
        os.environ.setdefault("MASTER_PORT", "29500")
        dist.init_process_group(backend=backend, init_method="env://", rank=self.rank,
                                world_size=self.world, timeout=datetime.timedelta(seconds=TIMEOUT))
        self._bar = {} if self.device.type == "cpu" else {"device_ids": [self.device.index]}
        self._selfcheck()
        self.log(f"{prim} {os.environ.get('TEST_DTYPE', 'bfloat16')} W={self.world} "
                 f"backend={backend} budget={human(BUDGET)} torch={torch.__version__}")

    def _selfcheck(self):
        """Slice-fill must match a standalone fill, or every regenerated reference is bogus."""
        a = torch.empty(64, dtype=DTYPE, device=self.device)
        a[16:32].normal_(generator=_gen(self.device, 0))
        b = torch.empty(16, dtype=DTYPE, device=self.device).normal_(generator=_gen(self.device, 0))
        if not torch.equal(a[16:32], b):
            sys.exit(f"[rank {self.rank}] [fatal] slice-fill != standalone RNG on {self.device.type}")

    def log(self, msg):
        if self.rank == 0:
            print(msg, flush=True)

    def fail(self, msg):
        self.failed = True
        print(f"[rank {self.rank}] FAIL {self.prim}: {msg}", flush=True)

    def sync(self):
        if self.device.type != "cpu":
            torch.accelerator.synchronize()

    def barrier(self):
        dist.barrier(**self._bar)
        self.sync()


@contextlib.contextmanager
def guard(ctx, what):
    """Turn a hung collective into a diagnosable failure instead of a dead job."""
    def bark():
        print(f"[rank {ctx.rank}] HANG {ctx.prim} {what} exceeded {TIMEOUT}s", flush=True)
        os._exit(2)

    t = threading.Timer(TIMEOUT, bark)
    t.daemon = True
    t.start()
    try:
        yield
    finally:
        t.cancel()


def check_finite(ctx, out):
    """Chunked: isfinite on the whole buffer would allocate a mask half its size."""
    for i in range(0, out.numel(), CHUNK):
        if not torch.isfinite(out[i : i + CHUNK]).all():
            ctx.fail(f"non-finite values in chunk starting at elem {i}")
            return False
    return True


def _first_diff(got, ref):
    return (got != ref).to(torch.uint8).argmax().item()


def check_regions(ctx, out, spans, keyfn, label="region"):
    """out is `world` contiguous regions; region r must be bit-identical to the data
    generated with keyfn(r). This is what catches misrouting. `spans` is a uniform
    element count or a per-region list. Compares the first chunk of sampled regions."""
    uniform = isinstance(spans, int)
    if not uniform:
        offs, acc = [], 0
        for s in spans:
            offs.append(acc)
            acc += s
    step = max(1, ctx.world // NCHECK)
    srcs = sorted({0, ctx.world - 1, ctx.rank, *range(0, ctx.world, step)})[:NCHECK]
    for r in srcs:
        o, n = (r * spans, spans) if uniform else (offs[r], spans[r])
        if n == 0:
            continue
        ref = chunk(n, 0, out.dtype, out.device, *keyfn(r))
        got = out[o : o + ref.numel()]
        if not torch.equal(got, ref):
            i = _first_diff(got, ref)
            ctx.fail(f"{label} {r} mismatch at elem {i}: got {got[i].item()} want {ref[i].item()}")
            return False
    ctx.log(f"local check ok ({len(srcs)}/{ctx.world} {label}s bitwise, isfinite ok)")
    return True


def check_scaled(ctx, out, scale, *key):
    """Full-buffer check that out == base * scale, chunk by chunk. Reports the observed
    relative error: bf16 reduction over many ranks is inherently lossy, so the pass
    threshold is generous and the measured number is the useful output."""
    n, worst = out.numel(), 0.0
    for j in range(nchunks(n)):
        ref = chunk(n, j, out.dtype, out.device, *key).float() * scale
        got = out[j * CHUNK : j * CHUNK + ref.numel()].float()
        denom = ref.abs().max().clamp(min=1e-12)
        worst = max(worst, ((got - ref).abs().max() / denom).item())
    if worst > RTOL:
        hint = " (near 1.0 => backend accumulated in low precision and the sum stagnated)" if worst > 0.5 else ""
        ctx.fail(f"max relative error {worst:.4f} exceeds {RTOL}{hint}")
        return False
    ctx.log(f"local check ok (full buffer, max rel err {worst:.5f}, tol {RTOL}, isfinite ok)")
    return True


def run(ctx, op, validate, prep=None):
    """Time `op` for ITERS iterations, then validate once. Exits nonzero if any rank failed."""
    times = []
    for i in range(ITERS):
        if prep:
            prep()
        ctx.barrier()
        t0 = time.perf_counter()
        with guard(ctx, f"iter {i}"):
            op()
        ctx.sync()
        times.append(time.perf_counter() - t0)
        ctx.log(f"iter {i}   {times[-1]:.3f}s")

    with guard(ctx, "validate"):
        validate()

    flag = torch.tensor([1 if ctx.failed else 0], device=ctx.device)
    with guard(ctx, "failure reduction"):
        dist.all_reduce(flag, op=dist.ReduceOp.MAX)
    mean = sum(times[1:]) / max(1, len(times) - 1)
    ctx.log(f"mean {mean:.3f}s (excl iter 0)   RESULT {'FAIL' if flag.item() else 'PASS'}")
    dist.destroy_process_group()
    sys.exit(int(flag.item()))
