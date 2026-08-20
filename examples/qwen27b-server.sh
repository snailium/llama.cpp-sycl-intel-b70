#!/usr/bin/env bash
# Example launch for Qwen3/Qwen3.6 ~27B on single Arc Pro B70 (SYCL)
# Adjust paths and device nodes for your system.

set -euo pipefail

MODEL=${MODEL:-/models/Qwen3-27B-Q4_K_M.gguf}
CTX=${CTX:-32768}

export ONEAPI_DEVICE_SELECTOR=level_zero:0
export SYCL_CACHE_PERSISTENT=0
export ZES_ENABLE_SYSMAN=1

exec llama-server \
  -m "$MODEL" \
  --n-gpu-layers 999 \
  --ctx-size "$CTX" \
  --flash-attn \
  --port 8080 --host 0.0.0.0 \
  "$@"
