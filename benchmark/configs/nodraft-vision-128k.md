# nodraft-vision-128k

- **Purpose:** The stable **agent-workhorse** base model — no speculation at all plus the vision projector, 128k context. Serves pure-text and tool-calling agent loads reliably, and is the baseline used to prove removing a 2B draft speeds up agent tasks.
- **Draft:** None (no `-md` / `--spec-type`).
- **Context:** 128k (`--ctx-size 131072`).
- **KV cache:** f16 (safe here because there is no draft model competing for VRAM).

## Full launch flags

```bash
--m /models/Qwen3.8-27B-Q4_K_M.gguf \
--mmproj /models/mmproj-Qwen3.8-27B-BF16.gguf \
--no-mmproj-offload \
--image-min-tokens 1024 \
--n-gpu-layers 999 \
--ctx-size 131072 \
--flash-attn on \
--port 8080 --host 0.0.0.0
```

Required environment:

```bash
ONEAPI_DEVICE_SELECTOR=level_zero:0
SYCL_CACHE_PERSISTENT=0
ZES_ENABLE_SYSMAN=1
```

## Memory footprint

- Main model Q4_K_M ≈ 18–19 GB + vision projector (`--no-mmproj-offload` keeps projector weights on CPU).
- No draft model → plenty of headroom even with f16 KV at 128k (the 5.9 GB MTP draft would have pushed it over the edge).

## When to use / avoid

- Use for long, deterministic agent/tool workloads where **success matters more than speed**.
- Proved that removing a 2B draft makes T3/T4 *faster* (21m vs 40m; 3m20 vs 4m11) — low-acceptance drafts are a drag.
- Vision quality is on par with a dual-3060 27B but decode is slow, so prefer it only when quality > speed.

## Linked report

- `benchmark/results/2026-08-20-nodraft-vision-128k.md`