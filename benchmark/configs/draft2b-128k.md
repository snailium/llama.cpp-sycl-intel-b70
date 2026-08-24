# draft2b-128k

- **Purpose:** Baseline configuration used for the early speculative-decoding comparison (2B draft). Demonstrates why a low-quality draft is a net drag and why q8_0 KV fixes overflow.
- **Draft:** `Qwen3.5-2B-Q4_K_M.gguf` (vocabulary-matched 2B draft), `--spec-draft-n-max 4`, simple draft type (`draft-simple`).
- **Context:** 128k (`--ctx-size 131072`).
- **KV cache:** f16 originally (→ OOM); **q8_0** is the tested fix (`--cache-type-k/v q8_0`).

## Full launch flags

Core flags (container `llama.cpp-sycl-b70:server`, entrypoint `llama-server`, exposing `:18080` → container `8080`):

```bash
--m /models/Qwen3.8-27B-Q4_K_M.gguf \
--n-gpu-layers 999 \
--ctx-size 131072 \
--cache-type-k q8_0 --cache-type-v q8_0 \
--flash-attn on \
--port 8080 --host 0.0.0.0
```

Draft model (2B, when present):

```bash
--md /models/Qwen3.5-2B-Q4_K_M.gguf \
--spec-type draft-simple \
--spec-draft-n-max 4
```

Required environment (see `examples/qwen27b-server.sh` for the full deployment):

```bash
ONEAPI_DEVICE_SELECTOR=level_zero:0
SYCL_CACHE_PERSISTENT=0
ZES_ENABLE_SYSMAN=1
```

## Memory footprint

- Main model Q4_K_M ≈ 18–19 GB.
- f16 KV at 128k with `n_slots` scaling exceeded 32 GB VRAM → overflow to host RAM (~0.2 t/s). Switching KV to **q8_0** roughly halves it and fits comfortably (observed ~20 GB, no spill).
- The 2B draft itself is small (~2 GB), but its low acceptance makes it a *slower-than-no-draft* net drag.

## When to use / avoid

- Use to isolate the effect of speculative decoding and to demonstrate the KV-overflow failure mode.
- **Avoid for production:** 2B draft acceptance (0.31–0.50) is a net slowdown. A high-quality BF16 MTP draft is the only speculative mode worth using.

## Linked report

- `benchmark/results/2026-08-20-draft2b-128k.md`