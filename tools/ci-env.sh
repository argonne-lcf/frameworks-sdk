#!/bin/bash
# Run a command with the same environment as the GitLab CI runner.
# Usage: ./ci-env.sh [-r <pipeline-id>] <command> [args...]

set -euo pipefail

while getopts ":r:" opt; do
	case "$opt" in
	r) export GITLAB_CI=1 CI_PIPELINE_ID="$OPTARG" ;;
	*) echo "Usage: $(basename "$0") [-r <pipeline-id>] <command> [args...]" >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))

[ "$#" -gt 0 ] || { echo "Usage: $(basename "$0") [-r <pipeline-id>] <command> [args...]" >&2; exit 2; }

case "$(hostname -f)" in
*sunspot.alcf.anl.gov)
	FRAMEWORKS_ROOT_DIR="/lus/tegu/projects/datascience/frameworks-ci"
	;;
*)
	FRAMEWORKS_ROOT_DIR="/lus/flare/projects/datascience/frameworks-ci"
	;;
esac
export FRAMEWORKS_ROOT_DIR

export FRAMEWORKS_PYTHON_VERSION="${FRAMEWORKS_PYTHON_VERSION:-3.12}"
export FRAMEWORKS_TORCH_VERSION="${FRAMEWORKS_TORCH_VERSION:-main}"
export FRAMEWORKS_TRITON_VERSION="${FRAMEWORKS_TRITON_VERSION:-main}"
export FRAMEWORKS_TORCHCCL_VERSION="${FRAMEWORKS_TORCHCCL_VERSION:-}"
export FRAMEWORKS_IPEX_VERSION="${FRAMEWORKS_IPEX_VERSION:-}"
export FRAMEWORKS_VLLM_VERSION="${FRAMEWORKS_VLLM_VERSION:-main}"
export FRAMEWORKS_VLLM_XPU_KERNELS_VERSION="${FRAMEWORKS_VLLM_XPU_KERNELS_VERSION:-main}"
export FRAMEWORKS_SDK_TESTS_VERSION="${FRAMEWORKS_SDK_TESTS_VERSION:-main}"
export FRAMEWORKS_DPCTL_VERSION="${FRAMEWORKS_DPCTL_VERSION:-0.22.1}"
export FRAMEWORKS_DPNP_VERSION="${FRAMEWORKS_DPNP_VERSION:-0.20.0}"

export HTTP_PROXY='http://proxy.alcf.anl.gov:3128'
export HTTPS_PROXY='http://proxy.alcf.anl.gov:3128'
export http_proxy="$HTTP_PROXY"
export https_proxy="$HTTPS_PROXY"

exec "$@"
