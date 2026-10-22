#!/usr/bin/env bash
# Launch the issue #30 candidate (v0.7.0) with the EXACT golden configuration.
#
# Golden source : llama.cpp-sycl-intel-b70/docs/GOLDEN-CONFIG.md (read from origin/main
#                 at run time; see evidence/golden-config-readback.txt)
# Image under test:
#   ghcr.io/snailium/llama.cpp-sycl-intel-b70/llama-sycl-b70:server-c26.35.39758.10-v0.7.0-20261016-0335
#   digest sha256:b265f4034978affce09c482374ce09dc5bf97852a3cede3bdabcbb84d90c2377
#
# NOTE ON THE MODELS MOUNT: the golden's paths are /models/<file>.gguf, so the host
# directory holding the GGUFs is mounted AS /models. On gpu-host the GGUFs live in
# /models/qwen3.8-27b/, hence the mount below.
#
# DEBUG_FLAG=-v is REQUIRED: agent-task (A1-A3) draft acceptance exists only in the
# server's print_timing output, because the dsh harness is the client and never sees
# the response-body timings block.
set -euo pipefail

CAND=${CAND:-ghcr.io/snailium/llama.cpp-sycl-intel-b70/llama-sycl-b70:server-c26.35.39758.10-v0.7.0-20261016-0335}
NAME=${NAME:-b70-dev-test-v070}
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
