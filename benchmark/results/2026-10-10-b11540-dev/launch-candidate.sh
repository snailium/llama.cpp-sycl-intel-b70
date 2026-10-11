#!/usr/bin/env bash
# Launch the issue #29 candidate (b11540) with the EXACT golden configuration.
#
# Golden source : llama.cpp-sycl-intel-b70 docs/GOLDEN-CONFIG.md on origin/main
#                 sha256 1f174ae9c8a2c69c10ebdda556ff715ac452827f35eb08172c658a31e3a41c6a
# Image under test:
#   ghcr.io/snailium/llama.cpp-sycl-intel-b70/llama-sycl-b70:server-dev-b11540-c26.35.39758.10-20261010-0349
#   digest sha256:8bfbe3755396d679b6691c9c79d156343ca176c4354e48897c201722b9b3f67c
#
# Deviations from GOLDEN-CONFIG.md §2: none. No `--network` is given (the golden
# form uses the default bridge plus `-p 18082:8080`); a previous attempt attached
# the container to a user network and the published port never came up, which is
# why this script pins the golden form explicitly.
#
# MODELS MOUNT: the golden's paths are /models/<file>.gguf, so the host directory
# holding the GGUFs is mounted AS /models. On gpu-host the GGUFs live in
# /models/qwen3.8-27b/.
set -euo pipefail

CAND=${CAND:-ghcr.io/snailium/llama.cpp-sycl-intel-b70/llama-sycl-b70:server-dev-b11540-c26.35.39758.10-20261010-0349}
NAME=${NAME:-b70-dev-test-b11540}
MODELS_DIR=${MODELS_DIR:-/models/qwen3.8-27b}
HOSTPORT=${HOSTPORT:-18082}

docker rm -f "$NAME" >/dev/null 2>&1 || true

docker run -d --name "$NAME" \
  --device /dev/dri \
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
