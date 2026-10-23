#!/usr/bin/env bash
# Relaunch the issue #30 candidate for the A3 rerun, with the EXACT golden config.
#
# The rerun changes ONE thing versus the first run: the repeat-tool-breaker
# limits. The first run's A3 looped 125x on one bash command and 130x on one
# web_fetch_file URL without ever tripping the gate, because the shipped
# defaults (exact/cmd/net/sink: 12, host: 16, window: 16) need 12 identical
# fingerprints inside a 16-call window and the run peaked at 9. The gate never
# fired, so the loop ran for the full hour.
#
# Measured on the first run's session (see evidence/a3-loop-analysis.txt):
#   identical bash command   : 125 total, max 9 in any 16-call window
#   identical web_fetch_file : 130 total, max 8 in any 16-call window
#
# The fix below sets limits that the observed loop DOES trip (exact/cmd/net 5,
# host 6), and sets onLimit: deny so the block is deterministic and needs no
# approval channel -- in headless mode an approval returns "unavailable", which
# the plugin treats fail-closed, and the onPre handler then suppresses further
# asks for the rest of the turn.
#
# The backend image, the golden config and the prompt are UNCHANGED.
set -euo pipefail

CAND=${CAND:-ghcr.io/snailium/llama.cpp-sycl-intel-b70/llama-sycl-b70:server-dev-b11706-c26.35.39758.10-20261017-0232}
NAME=${NAME:-b70-dev-test-b11706}
MODELS_DIR=${MODELS_DIR:-/models/qwen3.8-27b}
HOSTPORT=${HOSTPORT:-18082}

docker rm -f "$NAME" >/dev/null 2>&1 || true

docker run -d --name "$NAME" \
  --device /dev/dri \
  --network llm_backends_default \
  -v "$MODELS_DIR":/models:ro \
  -p "$HOSTPORT":8080 \
  -e ONEAPI_DEVICE_SELECTOR=level_zero:0 \
  -e SYCL_CACHE_PERSISTENT=0 \
  -e ZES_ENABLE_SYSMAN=1 \
  -e DEBUG_FLAG=-v \
  -e LLAMA_ARG_MODEL=/models/Qwen3.8-27B-Q4_K_M.gguf \
  -e LLAMA_ARG_MMPROJ=/models/mmproj-Qwen3.8-27B-Q8_0.gguf \
  -e LLAMA_ARG_MMPROJ_OFFLOAD=false \
  -e LLAMA_ARG_IMAGE_MIN_TOKENS=1024 \
  -e LLAMA_ARG_N_GPU_LAYERS=999 \
  -e LLAMA_ARG_CTX_SIZE=131072 \
  -e LLAMA_ARG_CACHE_TYPE_K=q8_0 \
  -e LLAMA_ARG_CACHE_TYPE_V=q8_0 \
  -e LLAMA_ARG_FLASH_ATTN=on \
  -e LLAMA_ARG_SPEC_DRAFT_MODEL=/models/mtp-Qwen3.8-27B-Q8_0.gguf \
  -e LLAMA_ARG_SPEC_TYPE=draft-mtp \
  -e LLAMA_ARG_SPEC_DRAFT_N_MAX=3 \
  -e LLAMA_ARG_SPEC_DRAFT_P_MIN=0.1 \
  -e LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_K=q8_0 \
  -e LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_V=q8_0 \
  -e LLAMA_ARG_REASONING=off \
  -e LLAMA_ARG_CHAT_TEMPLATE_KWARGS='{"enable_thinking":false,"preserve_thinking":false}' \
  -e LLAMA_ARG_N_PARALLEL=1 \
  -e LLAMA_ARG_TEMPERATURE=0.7 \
  -e LLAMA_ARG_TOP_P=0.80 \
  -e LLAMA_ARG_TOP_K=20 \
  -e LLAMA_ARG_MIN_P=0.0 \
  -e LLAMA_ARG_PRESENCE_PENALTY=1.5 \
  -e LLAMA_ARG_FREQUENCY_PENALTY=0.0 \
  -e LLAMA_ARG_REPEAT_PENALTY=1.0 \
  -e LLAMA_ARG_HOST=0.0.0.0 \
  -e LLAMA_ARG_PORT=8080 \
  --restart no \
  "$CAND"

docker ps --filter "name=$NAME" --format '{{.Names}} {{.Status}} ({{.ID}})'
