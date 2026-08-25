#!/usr/bin/env bash
# Recommended launch for Qwen3.8-27B (Q4_K_M) + MTP on single Arc Pro B70 (SYCL)
# Production (v0.3.0 + oneDNN/XMX image): F16 KV + 96k, Q4_0 MTP draft + Q8_0 mmproj,
# MTP3 (n-max 3, p-min 0.1), flash-attn, GGML_SYCL_FA_ONEDNN=1, thinking on.
# Based on benchmark 2026-08-25 R2 (v030-f16-96k-dnn-mtp3-q4): prefill 392 t/s,
# decode 26.2 t/s, draft acc 0.573, +1.5GB VRAM headroom vs Q8-MTP4.

set -euo pipefail

MODEL=${MODEL:-/models/Qwen3.8-27B-Q4_K_M.gguf}
MMProj=${MMProj:-/models/mmproj-Qwen3.8-27B-Q8_0.gguf}
DRAFT=${DRAFT:-/models/mtp-Qwen3.8-27B-Q4_0.gguf}
CTX=${CTX:-98304}

export ONEAPI_DEVICE_SELECTOR=level_zero:0
export SYCL_CACHE_PERSISTENT=0
export ZES_ENABLE_SYSMAN=1
export GGML_SYCL_FA_ONEDNN=1   # routes eligible FA prefills through the XMX path (needs oneDNN build)

exec llama-server \
  -m "$MODEL" \
  --mmproj "$MMProj" \
  --spec-draft-model "$DRAFT" \
  --spec-type draft-mtp \
  --spec-draft-n-max 3 \
  --spec-draft-p-min 0.1 \
  --spec-draft-type-k f16 \
  --spec-draft-type-v f16 \
  --n-gpu-layers 999 \
  --ctx-size "$CTX" \
  --cache-type-k f16 \
  --cache-type-v f16 \
  --flash-attn on \
  --port 8080 --host 0.0.0.0 \
  "$@"