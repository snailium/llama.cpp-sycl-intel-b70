# 2026-08-20 — nodraft-vision-128k

- **Config:** [nodraft-vision-128k](../configs/nodraft-vision-128k.md)
- **Result:** Full pass — **3/3 agent tasks** (`EXIT=0`), pure-text + vision, no speculation. Tests whether dropping the draft and adding the vision projector changes stability or speed.

## Summary

Removing the low-acceptance 2B draft and enabling the vision projector (`mmproj-BF16`) gives a **fully stable, speculation-free** 128k server. The key finding: **removing the 2B draft makes T3/T4 *faster*** (21m vs 40m; 3m20 vs 4m11) and the projector adds zero interference to text/tool workloads.

## Environment

- Server container `b70-qwen27b-vision` (`llama.cpp-sycl-b70:server`), endpoint `:18080/v1`.
- Main `Qwen3.8-27B-Q4_K_M.gguf` + `mmproj-Qwen3.8-27B-BF16.gguf` (vision, 931 MB), `--no-mmproj-offload --image-min-tokens 1024`, 128k ctx, f16 KV, **no draft**.
- Full launch: `-m /models/Qwen3.8-27B-Q4_K_M.gguf --mmproj /models/mmproj-Qwen3.8-27B-BF16.gguf --no-mmproj-offload --image-min-tokens 1024 --n-gpu-layers 999 --ctx-size 131072 --flash-attn on`.

## Results

### Smoke test (post-launch)

- `/v1/models` healthy; model id `/models/Qwen3.8-27B-Q4_K_M.gguf`.
- Text decode 23.2 t/s (200 tok / 8.6 s); no KV overflow; CPU 100%; normal memory.
- **mmproj does not affect pure-text / tool calls** in no-draft single-stream mode.

### T1/T2 generation baseline (same nodraft config)

Single-shot artifact tasks under the same thinking-off rules, as a clean generation reference:

| Task | Mode | E2E | Decode t/s | Output | Closed |
|------|------|-----|------------|--------|--------|
| T1 HTML | MAX_TOK 2400 | 110.4s | 23.0 t/s | 7634 ch | ❌ truncated, no `</html>` |
| T2 SVG | MAX_TOK 2400 | 106.1s | 22.9 t/s | 5275 ch | ❌ truncated, no `</svg>` |
| T1 HTML | no limit | **537.6s** | 21.9 t/s | 11,731 tok / 39,165 ch | ✅ `</html>` |
| T2 SVG | no limit | 126.4s | 22.8 t/s | 2,856 tok / 6,746 ch | ✅ `</svg>` |

- With no `max_tokens`, llama.cpp's server does **not truncate**; it finishes naturally (`finish_reason=stop`).
- Thinking-off is effective (`reasoning_len=0`, full content output).
- T1 *runs very long* without a token cap (11.7k tokens / 537s before it closes); T2 closes naturally at 2.8k.
- vs vLLM-MTP single-shot (T1 33.5s/72 t/s, T2 31.1s/77.6 t/s): llama.cpp generation E2E ≈ **3.3× slower**, decode ≈ 3.1–3.4× slower — the same no-XMX gap seen on agent loads.

### Agent tasks (3/3 EXIT=0)

| Task | Wall time | Result | Decode tokens | Effective rate* |
|------|-----------|--------|---------------|-----------------|
| T3 security review | **21m04s** | ✅ EXIT=0 | ~56.7k | ~44.8 tok/s |
| T4 host JSON | **3m20s** | ✅ EXIT=0 | ~16.2k | ~81.0 tok/s |
| T5 YOW snowfall | **1h07m02s** | ✅ EXIT=0 | ~92.9k | ~23.1 tok/s |

\* rate = llama.cpp `eval time` aggregated decode tokens ÷ total task wall time (includes reasoning/idle). Steady single-stream decode ≈ **15–23 t/s** (T5's long continuous generation lands ~23; T3/T4 short bursts higher). No draft-acceptance metric this run — that only exists with speculation.

### T5 result quality (rigorous, dual-source)

- YOW observed snowfall **258.6 cm** (as of 2026-08-18, daily series + ERA5 cross-check).
- Climate gap-fill for the remaining ~135 days (±74.8 cm) → best estimate for 2025-11-01 → 2026-12-31 approx **333 cm (±33 cm)**.
- Artifacts: report.md, `yow_daily_snow_*.csv`, `yow_obs.csv`, `yow_era5.json`, `ottawa_ccn.csv`.

### Loop detection (was it stuck?)

Analyzing the harness session (12k lines): **not a dead-loop** — 89 tool calls (88 bash + 1 web search) across 83 steps; **no adjacent duplicate commands**. T5's slowness came from the agent repeatedly probing the ECCC `api.weather.gc.ca` query format (real trial-and-error, not a hang).

## Cross-config comparison (agent task wall time)

| Task | nodraft+mmproj 128k | draft2b 128k | vLLM-MTP | vLLM non-MTP |
|------|--------------------|--------------|----------|--------------|
| T3 | **21m04s** ✅ | 40m51s ✅ | 31m48s ✅ | 3h00m ❌ (ctx) |
| T4 | **3m20s** ✅ | 4m11s ✅ | 1m51s ✅ | 17m |
| T5 | **1h07m** ✅ | 29m27s ✅ | crash 2/2 ❌ | 32m23s ✅ |

## Conclusion

1. **Splitting the 2B draft speeds up T3/T4** — a low-acceptance draft is a net drag; removing it wins.
2. T5's 1h07m is **agent route-choice variance** (heavy ECCC API exploration, 88 bash calls), not an engine regression.
3. Multimodal is **zero interference** on pure-text agent loads (3/3 stable).
4. llama.cpp remains the **only B70 backend passing all agent tasks** (vLLM-MTP crashes on T5).