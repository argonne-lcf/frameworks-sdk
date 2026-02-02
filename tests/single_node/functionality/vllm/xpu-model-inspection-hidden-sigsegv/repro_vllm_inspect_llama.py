import os
import tempfile

# Force cache miss each run so the subprocess inspection path is taken
os.environ["VLLM_CACHE_ROOT"] = tempfile.mkdtemp(prefix="vllm_cache_")

import vllm.model_executor.models.registry as r

ARCH = "LlamaForCausalLM"
model_obj = r.ModelRegistry.models[ARCH]

print("Model object:", type(model_obj), model_obj)
print("About to call _try_inspect_model_cls…")
out = r._try_inspect_model_cls(ARCH, model_obj)
print("Returned:", out)
