#!/usr/bin/env python3
"""
A simple script showing ProcessGroupXCCL list all_gather hidden-temp memory leak issue.

Run one MODE per process. All modes keep the user-visible src/output buffers
persistent except where noted.

Modes:
  list_hidden_temp
    Calls dist.all_gather(tensor_list, src). In ProcessGroupXCCL::allgather,
    this allocates hidden outputFlattened = newLikeFlat(outputTensors_), runs
    onecclAllGather into it, copies outputFlattened[j] to tensor_list[j], then
    outputFlattened is released.

  into_persistent
    Calls dist.all_gather_into_tensor(flat_out, src) with persistent flat_out.
    Same logical all-gather data movement, but no per-iteration temp.

  explicit_temp
    Manually spells out the list_hidden_temp pattern:
      temp = empty(world_size, tensor_size)
      dist.all_gather_into_tensor(temp.view(-1), src)
      tensor_list[j].copy_(temp[j])
      del temp
      empty_cache()
    This should leak at the same per-iteration rate as list_hidden_temp.

  temp_no_collective
    Allocates and frees the same temp size without passing it to XCCL.
    This should not leak, proving allocation + empty_cache alone is not enough.

Expected on affected stack with world_size=2, TENSOR_SIZE=100000000, bf16:
  hidden/output temp size = 2 * 100000000 * 2 bytes = 0.373 GiB.
  list_hidden_temp and explicit_temp should lose about 0.373 GiB per iter.
  into_persistent and temp_no_collective should stay flat after warmup.

Launch example:
  source scripts/activate.sh
  export ZE_FLAT_DEVICE_HIERARCHY=FLAT
  export MASTER_ADDR=127.0.0.1 MASTER_PORT=2620
  export MODE=list_hidden_temp
  mpiexec -n 2 -ppn 2 -env PALS_WORLD_SIZE=2 -- bash -lc '
    export RANK=$PALS_RANKID WORLD_SIZE=$PALS_WORLD_SIZE
    export LOCAL_RANK=$PALS_LOCAL_RANKID LOCAL_WORLD_SIZE=$PALS_LOCAL_SIZE
    python -u ./prove_list_allgather_hidden_temp.py
  '
"""

import os
import sys

import torch
import torch.distributed as dist


MODE = os.environ.get("MODE", "list_hidden_temp")
TENSOR_SIZE = int(os.environ.get("TENSOR_SIZE", "100000000"))
MAX_ITERS = int(os.environ.get("MAX_ITERS", "30"))
LOG_EVERY = int(os.environ.get("LOG_EVERY", "10"))
DTYPE = torch.bfloat16


def gib(nbytes: int) -> float:
    return nbytes / 1024**3


def mem(device: torch.device) -> tuple[float, float, float]:
    free, _ = torch.xpu.mem_get_info(device)
    return (
        gib(free),
        gib(torch.xpu.memory_allocated(device)),
        gib(torch.xpu.memory_reserved(device)),
    )


def log(rank: int, text: str) -> None:
    if rank == 0:
        print(text, flush=True)


dist.init_process_group("xccl")
rank = dist.get_rank()
world_size = dist.get_world_size()
local_rank = int(os.environ["LOCAL_RANK"])
torch.xpu.set_device(local_rank)
device = torch.device(f"xpu:{local_rank}")

src = torch.randn(TENSOR_SIZE, device=device, dtype=DTYPE)
tensor_list = [torch.empty_like(src) for _ in range(world_size)]
flat_out = torch.empty(TENSOR_SIZE * world_size, device=device, dtype=DTYPE)

expected_temp_gib = gib(TENSOR_SIZE * world_size * src.element_size())
log(
    rank,
    (
        f"mode={MODE} world={world_size} tensor_size={TENSOR_SIZE} dtype={DTYPE} "
        f"expected_temp={expected_temp_gib:.3f}GiB"
    ),
)
free0, alloc0, reserved0 = mem(device)
log(rank, f"initial | free={free0:6.2f}GiB alloc={alloc0:5.2f}GiB reserved={reserved0:5.2f}GiB")
log(
    rank,
    "persistent ptrs | src={} list={} flat_out={}".format(
        hex(src.data_ptr()), [hex(t.data_ptr()) for t in tensor_list], hex(flat_out.data_ptr())
    ),
)

if MODE not in {
    "list_hidden_temp",
    "into_persistent",
    "explicit_temp",
    "temp_no_collective",
}:
    raise ValueError(f"unknown MODE={MODE}")

first_after = None
last_after = None
for i in range(1, MAX_ITERS + 1):
    src.normal_()

    if MODE == "list_hidden_temp":
        dist.all_gather(tensor_list, src)
    elif MODE == "into_persistent":
        dist.all_gather_into_tensor(flat_out, src)
    elif MODE == "explicit_temp":
        temp = torch.empty((world_size, TENSOR_SIZE), device=device, dtype=DTYPE)
        dist.all_gather_into_tensor(temp.view(-1), src)
        for j in range(world_size):
            tensor_list[j].copy_(temp[j], non_blocking=True) # This is the same pattern in ProcessGroupXCCL 
        del temp
    elif MODE == "temp_no_collective":
        temp = torch.empty((world_size, TENSOR_SIZE), device=device, dtype=DTYPE)
        temp[rank].copy_(src, non_blocking=True)
        del temp

    torch.xpu.synchronize(device)
    torch.xpu.empty_cache()
    torch.xpu.synchronize(device)

    free, alloc, reserved = mem(device)
    if first_after is None:
        first_after = free
    last_after = free
    if rank == 0 and (i == 1 or i % LOG_EVERY == 0 or i == MAX_ITERS):
        drop_since_iter1 = first_after - free
        per_iter = drop_since_iter1 / max(i - 1, 1)
        print(
            f"iter {i:3d} | free={free:6.2f}GiB alloc={alloc:5.2f}GiB "
            f"reserved={reserved:5.2f}GiB drop_since_iter1={drop_since_iter1:6.2f}GiB "
            f"drop_per_iter={per_iter:5.3f}GiB",
            flush=True,
        )

per_iter = 0.0
if rank == 0 and first_after is not None and last_after is not None:
    per_iter = (first_after - last_after) / max(MAX_ITERS - 1, 1)
    print(
        f"summary | mode={MODE} expected_temp={expected_temp_gib:.3f}GiB "
        f"observed_drop_per_iter={per_iter:.3f}GiB",
        flush=True,
    )

dist.destroy_process_group()

if rank == 0 and per_iter > 0.0:
    sys.exit(1)
