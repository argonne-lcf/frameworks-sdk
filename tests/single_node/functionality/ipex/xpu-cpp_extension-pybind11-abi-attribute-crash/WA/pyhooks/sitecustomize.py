import importlib
import importlib.util
import sys
from pathlib import Path

def _patch_ipex_cpp_extension() -> None:
    patched = Path(__file__).with_name("cpp_extension.py")
    if not patched.exists():
        raise FileNotFoundError(f"Patched file not found: {patched}")

    # 1) Import the real parent package(s) so we don't shadow/break IPEX.
    import intel_extension_for_pytorch
    xpu_pkg = importlib.import_module("intel_extension_for_pytorch.xpu")

    # 2) Load the patched module object under the *real* fully-qualified name.
    fullname = "intel_extension_for_pytorch.xpu.cpp_extension"
    spec = importlib.util.spec_from_file_location(fullname, patched)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not create import spec for {fullname} from {patched}")

    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    # 3) Force future imports to resolve to patched module
    sys.modules[fullname] = mod

    # 4) Ensure `from intel_extension_for_pytorch.xpu import cpp_extension` uses patched one
    setattr(xpu_pkg, "cpp_extension", mod)

_patch_ipex_cpp_extension()

