#!/bin/bash
#
export http_proxy="proxy.alcf.anl.gov:3128"
export https_proxy="proxy.alcf.anl.gov:3128"

## Ratnam's environment
source /flare/Aurora_deployment/intel/pytorch/envs/torch_ipex_latest.env

export TORCH_LLM_ALLREDUCE=1
export CCL_ZE_IPC_EXCHANGE=drmfd
export VLLM_USE_V1=1
export VLLM_MLA_DISABLE=1
export VLLM_WORKER_MULTIPROC_METHOD=spawn
export VLLM_ENABLE_MOE_ALIGN_BLOCK_SIZE_TRITON=1
export ZE_FLAT_DEVICE_HIERARCHY=FLAT
export TORCH_DEVICE_BACKEND_AUTOLOAD=0
export SYCL_PI_LEVEL_ZERO_USE_IMMEDIATE_COMMANDLISTS=2
export OPT_W8A8_BLOCK_FP8_MATMUL=1
export XPU_CCL_BACKEND="xccl"

export HF_HOME="/flare/datasets/model-weights"
export HF_DATASETS_CACHE="/flare/datasets/model-weights"
export HF_MODULES_CACHE="/flare/datasets/model-weights"
#export HF_TOKEN="YOUR_HF_TOKEN"
export RAY_TMPDIR="/tmp"
export TMPDIR="/tmp"

export ZE_FLAT_DEVICE_HIERARCHY=FLAT
ray stop -f
export VLLM_HOST_IP=$(getent hosts $(hostname).hsn.cm.aurora.alcf.anl.gov | awk '{ print $1 }' | tr ' ' '\n' | sort | head -n 1)
export tiles=12
#ray --logging-level debug start --head --verbose --node-ip-address=$VLLM_HOST_IP --port=6379 --num-cpus=64 --num-gpus=$tiles&
#
export RAY_ADDRESS=$VLLM_HOST_IP:6379
#
export no_proxy="localhost,127.0.0.1" #Set no_proxy for the client to interact with the locally hosted model

export VLLM_HOST_IP=$(getent hosts $(hostname).hsn.cm.aurora.alcf.anl.gov | awk '{ print $1 }' | tr ' ' '\n' | sort | head -n 1)
vllm serve meta-llama/Llama-3.3-70B-Instruct --distributed-executor-backend mp --port 8000 \
    --tensor-parallel-size 8 --device xpu --dtype float16 --trust-remote-code --max-model-len 32768 --enforce-eager

#python -m vllm.entrypoints.openai.api_server --model=meta-llama/Llama-3.3-70B-Instruct --port 8000 \
#    --tensor-parallel-size 8 --device xpu --dtype float16 --trust-remote-code --max-model-len 32768


#python -m vllm.entrypoints.openai.api_server --model=meta-llama/Meta-Llama-3.1-8B --trust-remote-code --device xpu \
#    --distributed-executor-backend=mp --enforce-eager --max_model_len=1024 --pipeline-parallel-size=2 --tp=2 

