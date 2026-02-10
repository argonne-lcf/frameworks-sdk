# IPEX XPU cpp\_extension pybind11 ABI attribute crash reproducer

This directory contains a minimal reproducer for an IPEX XPU JIT extension build failure
triggered by newer PyTorch builds that do not export private `torch._C._PYBIND11_*` ABI
attributes.

## What it reproduces

When compiling a JIT extension via `intel_extension_for_pytorch.xpu.cpp_extension.load(...)`,
the IPEX extension build logic tries to read private PyTorch C-extension attributes:

- `torch._C._PYBIND11_COMPILER_TYPE`
- `torch._C._PYBIND11_STDLIB`
- `torch._C._PYBIND11_BUILD_ABI`

On affected PyTorch builds these attributes are missing, and the JIT build crashes with:

> `AttributeError: module 'torch._C' has no attribute '_PYBIND11_COMPILER_TYPE'`

This reproducer isolates the failure without involving DeepSpeed (which originally
hit the same IPEX XPU `cpp_extension` JIT codepath).

## What the script does

`repro_ipex_pybind11.py`:

- prints the active PyTorch version and whether `_PYBIND11_COMPILER_TYPE` exists
- writes a tiny C++/pybind11 extension source file (`pyb11_repro.cpp`)
- calls `intel_extension_for_pytorch.xpu.cpp_extension.load(...)` to force emission of
  a Ninja build file and trigger the same IPEX JIT compilation path
- the crash occurs while generating compile flags for the Ninja build when IPEX
  attempts to read `torch._C._PYBIND11_*` values

## How to run (reproducer)

```bash
python repro_ipex_pybind11.py
````

If the environment is affected, you should see a traceback ending in:

```text
AttributeError: module 'torch._C' has no attribute '_PYBIND11_COMPILER_TYPE'
```

---

## Workaround (WA)

The workaround lives under:

`WA/`

It works by:

1. Discovering the active IPEX install root/include/lib paths and exporting them into the
   environment (so compilation can find headers and shared libs).
2. Copying the upstream `cpp_extension.py` into a local override directory.
3. Applying a patch that changes `getattr(torch._C, "_PYBIND11_*")` to
   `getattr(torch._C, "_PYBIND11_*", None)` in the two relevant codepaths.
4. Using `sitecustomize.py` to force Python to import the patched module in place of
   the installed one, without modifying the global site-packages install.

### Files

* `WA/set_ipex_paths.sh`
  Discovers IPEX paths from the active Python environment and exports:
  `IPEX_ROOT`, `IPEX_INC`, `IPEX_LIBDIR`, and prepends `CPATH`, `LIBRARY_PATH`,
  `LD_LIBRARY_PATH`.

* `WA/pybind11_torchc_getattr_default.patch`
  Patch that guards the `_PYBIND11_*` lookups by providing a default of `None`.

* `WA/pyhooks/sitecustomize.py`
  Startup hook that replaces `intel_extension_for_pytorch.xpu.cpp_extension` with the
  patched copy located in the same directory.

### Steps

From the repro directory:

```bash
# 1) Set IPEX_ROOT / include / lib paths (also updates CPATH/LIBRARY_PATH/LD_LIBRARY_PATH)
source WA/set_ipex_paths.sh

# 2) Copy the upstream file into the override location expected by sitecustomize
cp "$IPEX_ROOT/xpu/cpp_extension.py" WA/pyhooks/cpp_extension.py

# 3) Apply the patch
(
  cd WA/pyhooks
  patch -p0 < ../pybind11_torchc_getattr_default.patch
)

# 4) Run the reproducer with sitecustomize active (must include WA/pyhooks on PYTHONPATH)
PYTHONPATH="$PWD/WA/pyhooks:$PYTHONPATH" python repro_ipex_pybind11.py
```

### Expected result (with workaround applied)

The JIT extension successfully builds and loads:

```text
torch: 2.10.0...
has _PYBIND11_COMPILER_TYPE: False
Emitting ninja build file .../build_repro/build.ninja...
Building extension module pyb11_repro...
[1/2] icpx ...
[2/2] icpx ... -o pyb11_repro.so
Loading extension module pyb11_repro...
Built module: <module 'pyb11_repro' from '.../pyb11_repro.so'>
OK: tensor([2.])
```

This confirms that the failure is solely due to the missing `_PYBIND11_*` attributes and
that guarding those lookups is sufficient to restore correct behavior.
