#!/bin/bash
## Apply vllm-xpu-kernels patch
## After cd into vllm-xpu-kernels

python <<'EOF'
import pathlib, re
f = pathlib.Path("csrc/utils/mem_info.cpp")
src = f.read_text()
new = re.sub(
    r"size_t getUsableMemory\(ze_device_handle_t& device\) \{.*?\n\}",
    (
        "size_t getUsableMemory(ze_device_handle_t& device) {\n"
        "  // Local build patch: driver L0 headers predate USABLEMEM_SIZE_EXT.\n"
        "  // Fall back to reporting total memory as \"usable\"; downstream KV-cache\n"
        "  // sizing treats a slightly over-optimistic value safely on dedicated GPUs.\n"
        "  return getTotalMemory(device);\n"
        "}"
    ),
    src, count=1, flags=re.DOTALL,
)
assert new != src, "patch didn't apply — check csrc/utils/mem_info.cpp"
f.write_text(new)
print("patched:", f)
EOF
