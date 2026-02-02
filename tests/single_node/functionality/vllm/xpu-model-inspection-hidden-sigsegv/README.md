# vLLM XPU model-inspection SIGSEGV reproducer

This directory contains a minimal reproducer for a crash seen when running vLLM on Aurora/XPU.

## What it reproduces

vLLM performs a **model "inspection" step** for each supported architecture.
In our case, inspecting `LlamaForCausalLM` triggers vLLM's model-registry inspection path, which spawns a helper subprocess to compute model metadata.
In this environment, that helper subprocess **dies with SIGSEGV (11)**, and vLLM later surfaces the failure as:

> `Model architectures ['LlamaForCausalLM'] failed to be inspected`

The crash happens before engine startup, so the full `vllm bench latency ...` command includes a lot of unrelated initialization noise (distributed init, TP, scheduler setup, etc.) that makes debugging difficult.

## What the script does

`repro_vllm_inspect_llama.py` is a tiny Python script that directly calls the same internal inspection code path that vLLM uses:

- forces a **cache miss** by setting `VLLM_CACHE_ROOT` to a fresh temp directory
- fetches the registered model entry for `"LlamaForCausalLM"` from `vllm.model_executor.models.registry.ModelRegistry.models`
- invokes `vllm.model_executor.models.registry._try_inspect_model_cls(...)`, which calls `model.inspect_model_cls()` (this is the step that launches the inspection subprocess)

If the environment is affected, this reproducer triggers the same SIGSEGV in seconds without MPI, tensor-parallel setup, or model loading.

## How to run

```bash
python repro_vllm_inspect_llama.py
```

