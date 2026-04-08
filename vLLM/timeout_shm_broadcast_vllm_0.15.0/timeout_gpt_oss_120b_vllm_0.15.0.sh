#!/bin/bash -x 
#
tstamp() {
     date +"%Y-%m-%d-%H%M%S"
}

export HF_TOKEN="hf_..."

## Proxies to clone from a compute node
export HTTP_PROXY=http://proxy.alcf.anl.gov:3128
export HTTPS_PROXY=http://proxy.alcf.anl.gov:3128
export http_proxy=http://proxy.alcf.anl.gov:3128
export http_proxy=http://proxy.alcf.anl.gov:3128
#
#
module add frameworks
export PYTHONNOUSERSITE=1

export HF_HOME="/lus/flare/projects/datasets/model-weights"
export HF_DATASETS_CACHE="/lus/flare/projects/datasets/model-weights"
export HF_MODULES_CACHE="/lus/flare/projects/datasets/model-weights"
##export HF_TOKEN="YOUR_HF_TOKEN"
export RAY_TMPDIR="/tmp"
export TMPDIR="/tmp"

## If you chose to move things over to `/tmp/ in any case
#export HF_HOME="/tmp/hf_home"
#export HF_DATASETS_CACHE="/tmp/hf_home"
#export HF_MODULES_CACHE="/tmp/hf_home"
#export HF_TOKEN="YOUR_HF_TOKEN"
#export RAY_TMPDIR="/tmp"
#export TMPDIR="/tmp"

export ZE_FLAT_DEVICE_HIERARCHY=FLAT

## For -tp 2
unset CCL_PROCESS_LAUNCHER
export CCL_PROCESS_LAUNCHER=None
export VLLM_WORKER_MULTIPROC_METHOD=spawn
export FI_MR_CACHE_MONITOR=userfaultfd

## Should not be needed with this iteration of the frameworks module
## But I keep it for documentation purposes
unset ONEAPI_DEVICE_SELECTOR
export ONEAPI_DEVICE_SELECTOR="opencl:gpu;level_zero:gpu"

## This is where this script lives
BENCH_DIR=/lus/flare/projects/datasets/softwares/testing/vllm-efforts

## This guy is going away, we need to figure out how to leverage 
## vLLM-native PyTorch profiler
export VLLM_TORCH_PROFILER_DIR=/lus/flare/projects/datasets/softwares/testing/vllm-efforts/profiles/llama3_8b

## A vLLM-native, keep things simple, for testing
export TOKENIZERS_PARALLELISM=false

## Uncomment it for lots and lots of chatter
#export VLLM_LOGGING_LEVEL=DEBUG

## These are to keep track of the underlying system level programming environment
echo "=== HOSTNAMEs ==="
printenv | grep "HOSTNAME"
echo "=== HOSTNAMEs ==="

echo "=== ENV CCL ==="
printenv | grep "CCL"
echo "=== ENV CCL ==="

echo "=== ENV CXI ==="
printenv | grep "CXI"
echo "=== ENV CXI ==="

echo "== MPI Provider=="
echo $MPI_PROVIDER
echo "== MPI Provider=="

## Being careful
ray stop -f
export no_proxy="localhost,127.0.0.1" #Set no_proxy for the client to interact with the locally hosted model

export VLLM_HOST_IP=$(getent hosts $(hostname).hsn.cm.aurora.alcf.anl.gov | awk '{ print $1 }' | tr ' ' '\n' | sort | head -n 1)

## May make the CACHE_ROOT to a hardcoded path if using with PBS
export VLLM_CACHE_ROOT=$PWD/.vllm_cache
#export VLLM_CACHE_ROOT=/tmp/hf_home/.vllm_cache
## Build cache for modelinfo, just one time
#python $PWD/vllm_build_all_modelinfo_caches.py --verbose

## The commented incantations are all the different cases that we check
## The uncommented one for the throughput with (ISL,OSL)

## --random-input-len, the number of input tokens per request (throughput only)
ISL=8192
## --random-output-len, the number of output tokens per request (throughput only)
OSL=8192
## A quick note: in each case, I used --num-prompts as default 1000 to trigger
## the error. Which takes a long time to run, did not check if a smaller value
## would trigger the same. May be try 300 and see if it hit that? 1000 keeps the
## benchmark reliability intact!
#
#
#echo "$(date) ${HOSTNAME} Before vLLM serve"
#
#VLLM_DISABLE_SINKS=1 vllm serve openai/gpt-oss-120b \
#  --dtype bfloat16 \
#  --tensor-parallel-size 8 \
#  --enforce-eager \
#  --distributed-executor-backend mp \
#  --trust-remote-code \
#  --port 6739
#
#echo "$(date) ${HOSTNAME} vLLM server is ready"

#VLLM_DISABLE_SINKS=1 vllm bench latency \
#  --model openai/gpt-oss-120b \
#  --dtype bfloat16 \
#  --tensor-parallel-size 8 \
#  --input-len ${ISL} \
#  --output-len ${OSL} \
#  --batch-size 1 \
#  --num-iters-warmup 2 \
#  --num-iters 2 2>&1 | tee ${BENCH_DIR}/logs/"LAT_gpt-oss-120b-TP8_COMP_I${ISL}_O${OSL}_LOG-$(tstamp).log"

#VLLM_DISABLE_SINKS=1 vllm bench latency \
#  --model openai/gpt-oss-120b \
#  --dtype bfloat16 \
#  --tensor-parallel-size 8 \
#  --data-parallel-size 1 \
#  --enable-expert-parallel \
#  --input_len ${ISL} \
#  --output_len ${OSL} \
#  --batch-size 1 \
#  --num-iters-warmup 2 \
#  --num-iters 2 \
#  --enforce-eager 2>&1 | tee ${BENCH_DIR}/logs/"LAT_gpt-oss-120b-TP8_EP8_I${ISL}_O${OSL}_LOG-$(tstamp).log"

VLLM_DISABLE_SINKS=1 vllm bench throughput \
  --model openai/gpt-oss-120b \
  --dtype bfloat16 \
  --tensor-parallel-size 8 \
  --random-input-len ${ISL} \
  --random-output-len ${OSL} 2>&1 | tee ${BENCH_DIR}/logs/"THRU_gpt-oss-120b-TP8_RAND_I${ISL}_O${OSL}_LOG-$(tstamp).log"

#VLLM_DISABLE_SINKS=1 vllm bench throughput \
#  --model openai/gpt-oss-120b \
#  --dtype bfloat16 \
#  --tensor-parallel-size 8 \
#  --input_len ${ISL} \
#  --output_len ${OSL} \
#  --enforce-eager 2>&1 | tee ${BENCH_DIR}/logs/"THRU_gpt-oss-120b-TP8_I${ISL}_O${OSL}_LOG-$(tstamp).log"

