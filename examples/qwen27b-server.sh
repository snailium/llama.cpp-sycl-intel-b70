#!/usr/bin/env bash
# Golden launcher — Qwen3.8-27B (Q4_K_M) + MTP on a single Intel Arc Pro B70 (SYCL).
#
# This mirrors the deployed production container exactly. Single source of truth:
#   docs/GOLDEN-CONFIG.md   (image digest, container spec, measured baseline)
#
#   image : ghcr.io/snailium/llama.cpp-sycl-intel-b70/llama-sycl-b70:stable  (llama.cpp v0.4.1,
#           compute-runtime 26.31.39395.13, oneDNN/XMX build)
#   config: q8_0 KV + 131072 ctx + Q8_0 MTP draft (n-max 3, p-min 0.1) + Q8_0 mmproj + thinking off
#
# Baseline from the v0.4.1 full suite (2026-09-14, benchmark/results/2026-09-14-v041-stable.md):
#   text prefill 470-490 tok/s weighted (570-600 in bursts), decode 41-46 tok/s short-context /
#   ~21 tok/s at deep context, draft acceptance 0.53-0.90 depending on task shape.
#
# Sampling: official Qwen3.8-27B instruct / non-thinking parameters (HF model card, 2026-08-30).
#   presence_penalty=1.5 is Qwen's own fix for verbosity/rambling in non-thinking mode.
#   Override any value by exporting MODEL/MMPROJ/DRAFT/CTX/TEMP/TOPP/TOPK/MINP/PRES/FREQ/REPEAT/PORT.
#   If you change a default here, update docs/GOLDEN-CONFIG.md in the same commit.

set -euo pipefail

MODEL=${MODEL:-/models/Qwen3.8-27B-Q4_K_M.gguf}
MMPROJ=${MMPROJ:-/models/mmproj-Qwen3.8-27B-Q8_0.gguf}
DRAFT=${DRAFT:-/models/mtp-Qwen3.8-27B-Q8_0.gguf}
CTX=${CTX:-131072}
PORT=${PORT:-8080}
HOSTADDR=${HOSTADDR:-0.0.0.0}

TEMP=${TEMP:-0.7}
TOPP=${TOPP:-0.80}
TOPK=${TOPK:-20}
MINP=${MINP:-0.0}
PRES=${PRES:-1.5}
FREQ=${FREQ:-0.0}
REPEAT=${REPEAT:-1.0}

# Mandatory runtime environment (never set GGML_SYCL_DISABLE_OPT).
export ONEAPI_DEVICE_SELECTOR=level_zero:0   # pin to the discrete GPU
export SYCL_CACHE_PERSISTENT=0               # mandatory: =1 SIGSEGVs on Xe2 during the first JIT
export ZES_ENABLE_SYSMAN=1                   # sysman queries (memory / utilisation)
# GGML_SYCL_FA_ONEDNN defaults to 1 in the source (XMX oneDNN SDPA prefill path).
# Export GGML_SYCL_FA_ONEDNN=0 only to A/B the XMX path off.

exec llama-server \
  -m "$MODEL" \
  --mmproj "$MMPROJ" \
  --no-mmproj-offload \
  --image-min-tokens 1024 \
  --n-gpu-layers 999 \
  --ctx-size "$CTX" \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --flash-attn on \
  --spec-draft-model "$DRAFT" \
  --spec-type draft-mtp \
  --spec-draft-n-max 3 \
  --spec-draft-p-min 0.1 \
  --spec-draft-type-k q8_0 \
  --spec-draft-type-v q8_0 \
  --reasoning off \
  --temp "$TEMP" --top-p "$TOPP" --top-k "$TOPK" --min-p "$MINP" \
  --presence-penalty "$PRES" --frequency-penalty "$FREQ" --repeat-penalty "$REPEAT" \
  --chat-template-kwargs '{"enable_thinking":false,"preserve_thinking":false}' \
  --host "$HOSTADDR" --port "$PORT" \
  "$@"
