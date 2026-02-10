#!/usr/bin/env bash
# Usage: source set_ipex_paths.sh

set -e

# Discover IPEX paths from the active Python environment
eval "$(python - <<'PY'
import os
import intel_extension_for_pytorch as ipex

root = os.path.dirname(ipex.__file__)
inc  = os.path.join(root, "include")
lib  = os.path.join(root, "lib")

print(f'export IPEX_ROOT="{root}"')
print(f'export IPEX_INC="{inc}"')
print(f'export IPEX_LIBDIR="{lib}"')
PY
)"

# Sanity checks (fail early if something is wrong)
if [ ! -d "$IPEX_ROOT" ]; then
  echo "ERROR: IPEX_ROOT does not exist: $IPEX_ROOT" >&2
  return 1
fi

if [ ! -f "$IPEX_INC/ipex.h" ]; then
  echo "ERROR: ipex.h not found in $IPEX_INC" >&2
  return 1
fi

if [ ! -f "$IPEX_LIBDIR/libintel-ext-pt-gpu.so" ]; then
  echo "ERROR: libintel-ext-pt-gpu.so not found in $IPEX_LIBDIR" >&2
  return 1
fi

# Prepend paths so they take precedence
export CPATH="$IPEX_INC:${CPATH}"
export LIBRARY_PATH="$IPEX_LIBDIR:${LIBRARY_PATH}"
export LD_LIBRARY_PATH="$IPEX_LIBDIR:${LD_LIBRARY_PATH}"

# Optional: make it obvious this ran
echo "IPEX_ROOT    = $IPEX_ROOT"
echo "IPEX_INC     = $IPEX_INC"
echo "IPEX_LIBDIR  = $IPEX_LIBDIR"

