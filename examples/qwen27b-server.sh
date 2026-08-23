#!/usr/bin/env bash
# Recommended launch for Qwen3.8-27B (Q4_K_M) + MTP on single Arc Pro B70 (SYCL)
# Based on final benchmark results (MTP4 + 128k + q8_0 KV)

set -euo pipefail

MODEL=${MODEL:-/models/Qwen3.8-27B-Q4_K_M.gguf}
MMProj=${MMProj:-/models/mmproj-Qwen3.8-27B-BF16.gguf}
DRAFT=${DRAFT:-/models/mtp-Qwen3.8-27B-BF16.gguf}
CTX=${CTX:-131072}

export ONEAPI_DEVICE_SELECTOR=level_zero:0
export SYCL_CACHE_PERSISTENT=0
export ZES_ENABLE_SYSMAN=1

exec llama-server \
  -m "$MODEL" \
  --mmproj "$MMProj" \
  --spec-draft-model "$DRAFT" \
  --spec-type draft-mtp \
  --spec-draft-n-max 4 \
  --spec-draft-p-min 0.1 \
  --n-gpu-layers 999 \
  --ctx-size "$CTX" \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --flash-attn on \
  --port 8080 --host 0.0.0.0 \
  "$@"
