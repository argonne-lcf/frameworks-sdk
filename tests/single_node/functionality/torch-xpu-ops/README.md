# XCCL `empty_cache` Repro Package

This package isolates an Intel XPU/XCCL memory leak triggered by freeing collective-participating device allocations with `torch.xpu.empty_cache()`.

## Files

- `prove_list_allgather_hidden_temp.py`: proof-style repro with four modes.
- `simple_allgather_into_tensor_empty_cache_leak.py`: minimal fresh-buffer `all_gather_into_tensor` leak.
- `simple_list_allgather_hidden_temp_leak.py`: persistent user-buffer `all_gather` repro showing the hidden list-API temp leak.
- `run_repros.sh`: runs the four proof modes.
- `SUMMARY.md`: result summary.
- `BUG_REPORT.md`: short bug report draft.

## Environment

Use the existing repo environment.

```bash
export ZE_FLAT_DEVICE_HIERARCHY=FLAT
```

## Run Proof Repro

```bash
./run_repros.sh
#or for running with Torchrun
./run_repros_torchrun.sh
```

Expected summary lines on the affected stack:

```text
list_hidden_temp   observed_drop_per_iter=0.373GiB
into_persistent   observed_drop_per_iter=0.000GiB
explicit_temp     observed_drop_per_iter=0.373GiB
temp_no_collective observed_drop_per_iter=0.000GiB
```

For a shorter/faster run, reduce tensor size:

```bash
TENSOR_SIZE=10000000 MAX_ITERS=30 ./run_repros.sh
```

## Run Individual Repros

