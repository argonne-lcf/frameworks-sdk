import os
import textwrap
import torch
from intel_extension_for_pytorch.xpu import cpp_extension as xpu_ext

print("torch:", torch.__version__)
print("has _PYBIND11_COMPILER_TYPE:", hasattr(torch._C, "_PYBIND11_COMPILER_TYPE"))

cpp = textwrap.dedent(r"""
    #include <torch/extension.h>

    torch::Tensor add(torch::Tensor a, torch::Tensor b) {
        return a + b;
    }

    PYBIND11_MODULE(TORCH_EXTENSION_NAME, m) {
        m.def("add", &add, "add");
    }
""").strip()

src_path = os.path.join(os.getcwd(), "pyb11_repro.cpp")
with open(src_path, "w") as f:
    f.write(cpp)

build_dir = os.path.join(os.getcwd(), "build_repro")
os.makedirs(build_dir, exist_ok=True)   # <-- important

mod = xpu_ext.load(
    name="pyb11_repro",
    sources=[src_path],
    extra_cflags=["-O0"],
    build_directory=build_dir,
    verbose=True,
    is_python_module=True,
    keep_intermediates=True,
)

print("Built module:", mod)
print("OK:", mod.add(torch.ones(1), torch.ones(1)))

