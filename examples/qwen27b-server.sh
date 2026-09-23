#!/usr/bin/env bash
# Golden launcher — Qwen3.8-27B (Q4_K_M) + MTP on a single Intel Arc Pro B70 (SYCL).
#
# This mirrors the deployed production container exactly. Single source of truth:
#   docs/GOLDEN-CONFIG.md   (image digest, container spec, measured baseline)
#
#   image : ghcr.io/snailium/llama.cpp-sycl-intel-b70/llama-sycl-b70:stable
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
#
# ---------------------------------------------------------------------------
# CONFIGURATION IS DELIVERED AS LLAMA_ARG_* ENVIRONMENT VARIABLES, NOT FLAGS.
#
# llama.cpp maps every server argument to an LLAMA_ARG_* variable, so the whole
# config can be an environment block — which is what docker-compose.yml and the
# deployed container use. Passing no flags at all is deliberate: it keeps this
# script and the compose file describing the same thing in the same shape.
#
# ⚠️ MINIMUM VERSION — READ BEFORE CHANGING THE IMAGE TAG
#
#   | variable group                              | floor        |
#   |---------------------------------------------|--------------|
#   | model / ctx / KV / flash-attn / offload /   | older than   |
#   | mmproj / spec-decode / parallel / host/port | v0.4.1       |
#   | **sampling: TEMPERATURE, TOP_P, MIN_P,      | **>= b11078**|
#   | PRESENCE_PENALTY, FREQUENCY_PENALTY,        |              |
#   | REPEAT_PENALTY**                            |              |
#
# The six sampling variables were added in commit e0dff5847 (#27380), first
# shipped in **b11078**. So:
#
#   * **v0.4.1 (b10964) and older do NOT support them** — they are silently
#     ignored and the server runs with its own defaults (temp 0.8, top_p 0.95,
#     ...), changing output quality with no error at all.
#   * **Any dev build before b11078 has the same gap.**
#   * **v0.5.0 (>= b11146) is fine.**
#
# If you must run an image older than b11078, set USE_SAMPLING_FLAGS=1 and the
# six sampling values are passed as command-line flags instead (they win over
# any env var, so both paths stay correct).
# ---------------------------------------------------------------------------

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

# Set to 1 for images older than b11078, where the sampling env vars do not exist.
USE_SAMPLING_FLAGS=${USE_SAMPLING_FLAGS:-0}

# --- mandatory runtime environment (never set GGML_SYCL_DISABLE_OPT) --------
export ONEAPI_DEVICE_SELECTOR=level_zero:0   # pin to the discrete GPU
export SYCL_CACHE_PERSISTENT=0               # mandatory: =1 SIGSEGVs on Xe2 during the first JIT
export ZES_ENABLE_SYSMAN=1                   # sysman queries (memory / utilisation)
# GGML_SYCL_FA_ONEDNN defaults to 1 in the source (XMX oneDNN SDPA prefill path).
# Export GGML_SYCL_FA_ONEDNN=0 only to A/B the XMX path off.

# --- server configuration, as LLAMA_ARG_* ----------------------------------
export LLAMA_ARG_MODEL="$MODEL"
export LLAMA_ARG_MMPROJ="$MMPROJ"
export LLAMA_ARG_MMPROJ_OFFLOAD=false        # == --no-mmproj-offload
export LLAMA_ARG_IMAGE_MIN_TOKENS=1024
export LLAMA_ARG_N_GPU_LAYERS=999
export LLAMA_ARG_CTX_SIZE="$CTX"
export LLAMA_ARG_CACHE_TYPE_K=q8_0
export LLAMA_ARG_CACHE_TYPE_V=q8_0
export LLAMA_ARG_FLASH_ATTN=on
export LLAMA_ARG_SPEC_DRAFT_MODEL="$DRAFT"
export LLAMA_ARG_SPEC_TYPE=draft-mtp
export LLAMA_ARG_SPEC_DRAFT_N_MAX=3
export LLAMA_ARG_SPEC_DRAFT_P_MIN=0.1
export LLAMA_ARG_SPEC_DRAFT_TYPE_K=q8_0
export LLAMA_ARG_SPEC_DRAFT_TYPE_V=q8_0
export LLAMA_ARG_REASONING=off
export LLAMA_ARG_CHAT_TEMPLATE_KWARGS='{"enable_thinking":false,"preserve_thinking":false}'
export LLAMA_ARG_N_PARALLEL=1
export LLAMA_ARG_HOST="$HOSTADDR"
export LLAMA_ARG_PORT="$PORT"

# --- sampling: env vars only on llama.cpp >= b11078 ------------------------
if [ "$USE_SAMPLING_FLAGS" = "1" ]; then
  SAMPLING_FLAGS=(
    --temp "$TEMP" --top-p "$TOPP" --top-k "$TOPK" --min-p "$MINP"
    --presence-penalty "$PRES" --frequency-penalty "$FREQ" --repeat-penalty "$REPEAT"
  )
else
  SAMPLING_FLAGS=()
  export LLAMA_ARG_TEMPERATURE="$TEMP"
  export LLAMA_ARG_TOP_P="$TOPP"
  export LLAMA_ARG_TOP_K="$TOPK"
  export LLAMA_ARG_MIN_P="$MINP"
  export LLAMA_ARG_PRESENCE_PENALTY="$PRES"
  export LLAMA_ARG_FREQUENCY_PENALTY="$FREQ"
  export LLAMA_ARG_REPEAT_PENALTY="$REPEAT"
fi

exec llama-server "${SAMPLING_FLAGS[@]}" "$@"
