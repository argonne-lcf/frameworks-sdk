#!/usr/bin/env python3
"""
vllm_make_modelinfo_cache.py

Pre-populate vLLM's model-info cache to avoid the model-inspection subprocess.

Works with vLLM versions that use vllm.model_executor.models.registry._LazyRegisteredModel
and vllm.model_executor.models.registry._ModelInfo.

Usage examples:

  # LlamaForCausalLM
  export VLLM_CACHE_ROOT=$PWD/.vllm_cache
  python vllm_make_modelinfo_cache.py vllm.model_executor.models.llama:LlamaForCausalLM

  # Another built-in model class
  python vllm_make_modelinfo_cache.py vllm.model_executor.models.mistral:MistralForCausalLM

  # Print what it wrote and verify existence
  python vllm_make_modelinfo_cache.py --verbose vllm.model_executor.models.llama:LlamaForCausalLM

Notes:
- This script targets model *implementation classes inside vLLM*, not Hugging Face model IDs.
- You must set VLLM_CACHE_ROOT (recommended) or it will use vLLM's default cache root.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
import importlib


def parse_target(s: str) -> tuple[str, str]:
    """
    Parse "module:ClassName" or "module.ClassName" into (module, class).
    """
    if ":" in s:
        module_name, class_name = s.split(":", 1)
        module_name, class_name = module_name.strip(), class_name.strip()
        if not module_name or not class_name:
            raise ValueError("Invalid target format. Use module:ClassName")
        return module_name, class_name

    # allow module.ClassName
    if "." in s:
        module_name, class_name = s.rsplit(".", 1)
        return module_name.strip(), class_name.strip()

    raise ValueError("Invalid target format. Use module:ClassName or module.ClassName")


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Create/refresh vLLM model-info cache for a vLLM model class."
    )
    ap.add_argument(
        "target",
        help="Model class target, e.g. vllm.model_executor.models.llama:LlamaForCausalLM",
    )
    ap.add_argument(
        "--cache-root",
        default=os.environ.get("VLLM_CACHE_ROOT", ""),
        help="Cache root directory (defaults to $VLLM_CACHE_ROOT if set).",
    )
    ap.add_argument(
        "--verbose",
        action="store_true",
        help="Print extra details.",
    )

    args = ap.parse_args()
    module_name, class_name = parse_target(args.target)

    # Import vLLM registry
    try:
        import vllm.model_executor.models.registry as r
    except Exception as e:
        print(f"ERROR: Failed to import vLLM registry: {e!r}", file=sys.stderr)
        return 2

    # Ensure internal APIs exist for the build
    Lazy = getattr(r, "_LazyRegisteredModel", None)
    ModelInfo = getattr(r, "_ModelInfo", None)
    if Lazy is None or ModelInfo is None:
        print(
            "ERROR: This vLLM build does not expose _LazyRegisteredModel/_ModelInfo "
            "in vllm.model_executor.models.registry; cannot write cache safely.",
            file=sys.stderr,
        )
        return 3

    # Choose cache root
    if args.cache_root:
        os.environ["VLLM_CACHE_ROOT"] = args.cache_root
    cache_root = os.environ.get("VLLM_CACHE_ROOT", "")
    if args.verbose:
        print("VLLM_CACHE_ROOT =", cache_root or "<vLLM default>")

    # Resolve the module file to hash it
    try:
        mod = importlib.import_module(module_name)
    except Exception as e:
        print(f"ERROR: Could not import module '{module_name}': {e!r}", file=sys.stderr)
        return 4

    model_py = Path(getattr(mod, "__file__", "") or "")
    if not model_py.exists():
        print(
            f"ERROR: Could not locate source file for module '{module_name}' "
            f"(got __file__={model_py}).",
            file=sys.stderr,
        )
        return 5

    # Validate the class exists
    if not hasattr(mod, class_name):
        print(
            f"ERROR: Module '{module_name}' has no attribute '{class_name}'.",
            file=sys.stderr,
        )
        return 6

    # Create the lazy entry and compute ModelInfo in-process
    try:
        lazy = Lazy(module_name=module_name, class_name=class_name)
        cls = lazy.load_model_cls()
        mi = ModelInfo.from_model_cls(cls)
    except Exception as e:
        print(
            f"ERROR: Failed to compute ModelInfo for {module_name}:{class_name}: {e!r}",
            file=sys.stderr,
        )
        return 7

    # Compute the module hash exactly like registry does (safe_hash over file bytes)
    try:
        module_hash = r.safe_hash(model_py.read_bytes(), usedforsecurity=False).hexdigest()
    except Exception as e:
        print(f"ERROR: Failed to hash module file {model_py}: {e!r}", file=sys.stderr)
        return 8

    # Save cache using vLLM's own implementation (ensures correct filename scheme)
    try:
        lazy._save_modelinfo_to_cache(mi, module_hash)
        cache_path = lazy._get_cache_dir() / lazy._get_cache_filename()
    except Exception as e:
        print(f"ERROR: Failed to save cache: {e!r}", file=sys.stderr)
        return 9

    print(f"OK: wrote {cache_path}")
    if args.verbose:
        print("model file :", model_py)
        print("hash       :", module_hash)
        print("exists     :", cache_path.exists())

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

