# golden-v041-q8-128k-mtp3 — production configuration (llama.cpp v0.4.1)

> **Status: GOLDEN (current production).** Full canonical description, including the container spec
> and image digest: [`docs/GOLDEN-CONFIG.md`](../../docs/GOLDEN-CONFIG.md). Test evidence:
> [`benchmark/results/2026-09-14-v041-stable.md`](../results/2026-09-14-v041-stable.md).
>
> Supersedes [`v030-f16-96k-dnn-mtp3-q4`](./v030-f16-96k-dnn-mtp3-q4.md) (the v0.3.0-era
> "F16 KV + 96k + Q4_0 MTP" recommendation) as of 2026-09-14.

## Image

| Item | Value |
|---|---|
| Tag | `ghcr.io/snailium/llama.cpp-sycl-intel-b70/llama-sycl-b70:server-c26.31.39395.13-v0.4.1-20260914-2252` (= `:stable`) |
| Digest | `sha256:5af1e2290fc53930a5f323ac5d26dd9faa9737109336ecdc18aee085b20ef25b` |
| llama.cpp | v0.4.1 |
| Intel stack | compute-runtime 26.31.39395.13 / IGC 2.40.13 / Level Zero 1.32.0 |
| oneDNN / XMX | built with `GGML_SYCL_DNN=ON`; `GGML_SYCL_FA_ONEDNN` defaults to 1 |

## Configuration

```bash
-m /models/Qwen3.8-27B-Q4_K_M.gguf
--mmproj /models/mmproj-Qwen3.8-27B-Q8_0.gguf --no-mmproj-offload --image-min-tokens 1024
--n-gpu-layers 999
--ctx-size 131072
--cache-type-k q8_0 --cache-type-v q8_0
--flash-attn on
--spec-draft-model /models/mtp-Qwen3.8-27B-Q8_0.gguf
--spec-type draft-mtp --spec-draft-n-max 3 --spec-draft-p-min 0.1
--spec-draft-type-k q8_0 --spec-draft-type-v q8_0
--reasoning off
--temp 0.7 --top-p 0.80 --top-k 20 --min-p 0.0
--presence-penalty 1.5 --frequency-penalty 0.0 --repeat-penalty 1.0
--chat-template-kwargs '{"enable_thinking":false,"preserve_thinking":false}'
```

Container: `/dev/dri`, models mounted read-only at `/models`, port `18082 -> 8080`, env
`ONEAPI_DEVICE_SELECTOR=level_zero:0 SYCL_CACHE_PERSISTENT=0 ZES_ENABLE_SYSMAN=1`, `restart=no`.

## Why this config

- **`q8_0` KV + 128k** — halves KV versus f16 (needed to fit a speculative draft plus a full 128k
  window in 32 GB) while still reaching the XMX oneDNN SDPA prefill path: since upstream #25874
  (merged 2026-08-04) non-f16 KV is dequantized to f16 and then runs through SDPA at prefill
  lengths. Only BF16 and IQ* KV types are excluded.
- **MTP3 over MTP4** — the fourth speculative position collapses on agent-shaped workloads
  (per-position acceptance 0.81 / 0.66 / 0.54 / 0.46); MTP3 is faster wall-clock on long tasks.
- **Q8_0 MTP draft** — a low-acceptance 2B draft is a net slowdown; Q8_0 keeps acceptance high and
  leaves VRAM headroom versus the BF16 draft.
- **Thinking off at both layers** — `--reasoning off` handles response parsing, the template-level
  `enable_thinking:false` stops generation. Both are required.
- **Official Qwen non-thinking sampling** — `presence_penalty 1.5` is Qwen's own verbosity fix.

## Measured baseline (v0.4.1 full suite, 2026-09-14)

| Task | fill (tok/s) | TTFT med/mean | decode (tok/s) | draft acc |
|---|---|---|---|---|
| t1_html | 64.0 | 0.67 s | 41.4 | 0.744 |
| t2_svg | 49.5 | 0.65 s | 46.2 | 0.897 |
| t3_security (agent) | 472.3 | 3.90 / 9.12 s | 20.82 | 0.532 |
| t4_hostinfo (agent) | 492.2 | 3.55 / 8.24 s | 37.57 | 0.809 |
| t5_snowfall (agent) | 298.6 | 0.96 / 1.59 s | 33.93 | 0.812 |
| V1 game / V2 pcb / V3 tire | 32.5 / 59.3 / 29.6 | 110.8 / 18.6 / 141.0 s | 34.1 / 36.8 / 40.1 | 0.574 / 0.606 / 0.733 |

Stability: `RestartCount=0`, `OOMKilled=false`, zero SIGSEGV / allocation failure /
`UR_RESULT_ERROR*` / device-lost / GPU-hang events across the whole suite.

## Memory notes

Single B70, 32 GB VRAM: main model ~17.7 GB + MTP draft ~3 GB (Q8_0) + mmproj on CPU + unified KV
cache for 131072 tokens at q8_0. A second GPU container cannot co-exist with this one; a candidate
image has to replace it.

## Mirrors

[`examples/qwen27b-server.sh`](../../examples/qwen27b-server.sh) (bare-metal launcher) and
[`docker-compose.yml`](../../docker-compose.yml) (container) implement exactly this configuration.
