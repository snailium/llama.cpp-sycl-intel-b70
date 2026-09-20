# Golden configuration — B70 production stack

> **This is the single source of truth for what we actually deploy.** Everything else in this
> repository is evidence, history, or experiment. If a document disagrees with this file, this
> file wins (and the other document should be dated/superseded).
>
> As of **2026-09-20** (llama.cpp **v0.4.1**, promoted from issue #18).
> Host placeholders are used on purpose: this repo is public — **never commit internal IPs,
> usernames, or absolute host paths here.**

## 1. Image

| Item | Value |
|---|---|
| Image (pinned) | `ghcr.io/snailium/llama.cpp-sycl-intel-b70/llama-sycl-b70:server-c26.35.39758.10-v0.4.1` |
| Image (floating) | `…:stable` |
| Digest (both tags) | `sha256:d7f303202d55357da11e3e6f0c7dae3bed6f381dbeb930ead4208d0fcb1742f5` |
| llama.cpp | v0.4.1 (upstream tag; build commit `b29c606`) |
| Intel stack | compute-runtime `26.35.39758.10` / IGC `v2.41.5` / Level Zero loader `1.28.6` |
| oneDNN / XMX | `-DGGML_SYCL_DNN=ON`; `libdnnl.so.3` linked; runtime gate `GGML_SYCL_FA_ONEDNN` **defaults to 1** |
| Entrypoint | `/app/llama-server` (image default — **never override it**) |

Verify a pulled image before serving:

```bash
docker run --rm --entrypoint /bin/bash <image> -lc '
  ldd /app/libggml-sycl.so | grep -i dnnl
  strings /app/libggml-sycl.so | grep -m1 g_ggml_sycl_fa_onednn'
```

## 2. Container spec

```bash
docker run -d --name b70-llama-golden \
  --device /dev/dri \
  -v <models-dir>:/models:ro \
  -p 18082:8080 \
  -e ONEAPI_DEVICE_SELECTOR=level_zero:0 \
  -e SYCL_CACHE_PERSISTENT=0 \
  -e ZES_ENABLE_SYSMAN=1 \
  --restart no \
  <image> \
  <server args — see §3>
```

| Setting | Value | Why |
|---|---|---|
| Device | `/dev/dri` (whole directory) | the Arc GPU is `renderD128`; passing the directory survives card index changes |
| Models | host models dir mounted **read-only** at `/models` | weights never need to be writable |
| Port | host `18082` → container `8080` | 8080 stays free on the host |
| `ONEAPI_DEVICE_SELECTOR` | `level_zero:0` | pin to the discrete GPU (host also has an AMD iGPU) |
| `SYCL_CACHE_PERSISTENT` | `0` | **mandatory** — `1` SIGSEGVs on Xe2 during first JIT |
| `ZES_ENABLE_SYSMAN` | `1` | sysman queries (memory/utilisation) |
| `GGML_SYCL_FA_ONEDNN` | *unset* (defaults to `1`) | XMX SDPA path; only set it explicitly to force `0` for A/B |
| `--restart` | `no` | deliberate: GPU containers must be brought up consciously after host/PCIe events |

## 3. Server arguments (golden, exact)

```bash
-m /models/Qwen3.8-27B-Q4_K_M.gguf
--mmproj /models/mmproj-Qwen3.8-27B-Q8_0.gguf
--no-mmproj-offload
--image-min-tokens 1024
--n-gpu-layers 999
--ctx-size 131072
--cache-type-k q8_0
--cache-type-v q8_0
--flash-attn on
--spec-draft-model /models/mtp-Qwen3.8-27B-Q8_0.gguf
--spec-type draft-mtp
--spec-draft-n-max 3
--spec-draft-p-min 0.1
--spec-draft-type-k q8_0
--spec-draft-type-v q8_0
--reasoning off
--temp 0.7 --top-p 0.80 --top-k 20 --min-p 0.0
--presence-penalty 1.5 --frequency-penalty 0.0 --repeat-penalty 1.0
--chat-template-kwargs '{"enable_thinking":false,"preserve_thinking":false}'
-v --host 0.0.0.0 --port 8080
```

Rationale, group by group:

- **Context / KV** — `131072` context with **`q8_0` KV**. q8_0 halves KV versus f16 and is what makes
  full 128k + a speculative draft fit in 32 GB. (f16 is the native no-dequant path for the oneDNN
  SDPA kernel, but it costs ~2× KV; see `docs/B70-TUNING.md`.)
- **Speculative decoding** — MTP head as a **separate Q8_0 draft model**, `--spec-draft-n-max 3`.
  MTP3 beats MTP4 on agent workloads (position-4 acceptance collapses); the draft uses q8_0 KV for
  the same VRAM reason as the main model.
- **Vision** — mmproj stays on the **CPU** (`--no-mmproj-offload`) with `--image-min-tokens 1024`.
- **Thinking** — `--reasoning off` (response-parsing layer) **and** a template-level
  `enable_thinking:false` default. Both are needed: the first controls where thoughts are placed,
  the second stops Qwen from generating them at all.
- **Sampling** — official Qwen3.8-27B non-thinking parameters (`presence_penalty 1.5` is Qwen's own
  fix for verbosity — do not lower temperature instead).
- **`-v`** — verbose logging. Note this makes log lines **contain full request bodies**; always bound
  output width when grepping.

## 4. Model files

| File | Size | Role |
|---|---|---|
| `Qwen3.8-27B-Q4_K_M.gguf` | 17.67 GB | main model (arch `qwen35`, dense, 64 layers) |
| `mmproj-Qwen3.8-27B-Q8_0.gguf` | 0.59 GB | vision projector |
| `mtp-Qwen3.8-27B-Q8_0.gguf` | 2.95 GB | MTP speculative head (separate GGUF, 18 tensors) |

The main GGUF carries **no** NextN layers — the MTP head lives only in the draft file.

## 5. Bring-up and verification

```bash
# 1) readiness: /health 503 ("Loading model") is normal — poll /v1/models until 200
until [ "$(curl -s -o /dev/null -w '%{http_code}' http://<b70-host>:18082/v1/models)" = 200 ]; do sleep 10; done

# 2) first completion must return 200
curl -s http://<b70-host>:18082/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model":"/models/Qwen3.8-27B-Q4_K_M.gguf",
  "messages":[{"role":"user","content":"reply with exactly: ok"}],
  "max_tokens":16,"chat_template_kwargs":{"enable_thinking":false}}'

# 3) thinking really off: reasoning_content must be absent/null in the response
# 4) stability after a load: RestartCount=0, no OOMKilled
docker inspect <container> --format 'restart={{.RestartCount}} status={{.State.Status}} oom={{.State.OOMKilled}}'
```

Model load takes ~2 minutes (17.7 GB main + draft + mmproj) before `/v1/models` answers 200.

## 6. Expected performance (v0.4.1 full suite, golden config)

Measured 2026-09-14 on a single Arc Pro B70 with the exact configuration above, on the
compute-runtime `26.31.39395.13` artifact. Superseded runs on `26.35.39758.10` (issues #18, #19)
found these numbers **unchanged within noise** — see each report's comparison table.
Full report: [`benchmark/results/2026-09-14-v041-stable.md`](../benchmark/results/2026-09-14-v041-stable.md).

| Task | fill (tok/s) | TTFT med/mean | decode (tok/s) | draft acc |
|---|---|---|---|---|
| t1_html | 64.0 (43-tok prompt) | 0.67 s | 41.4 | 0.744 |
| t2_svg | 49.5 (32-tok prompt) | 0.65 s | 46.2 | 0.897 |
| t3_security (agent) | 472.3 | 3.90 / 9.12 s | 20.82 | 0.532 |
| t4_hostinfo (agent) | 492.2 | 3.55 / 8.24 s | 37.57 | 0.809 |
| t5_snowfall (agent) | 298.6 | 0.96 / 1.59 s | 33.93 | 0.812 |
| V1 game (vision) | 32.5 | 110.8 s | 34.1 | 0.574 |
| V2 pcb (vision) | 59.3 | 18.6 s | 36.8 | 0.606 |
| V3 tire (vision) | 29.6 | 141.0 s | 40.1 | 0.733 |

Reading the numbers:

- **Text prefill (fill)** is the XMX/oneDNN SDPA path — 470–490 tok/s weighted on agent tasks,
  570–600 tok/s in bursts. Quantized KV gets there via dequantize→f16 followed by SDPA (upstream
  #25874, merged 2026-08-04).
- **Decode** is memory-bound: 40–46 tok/s on short contexts, ~21 tok/s at the deep end of a long
  agent task. This is the structural ceiling for a single stream on this part (upstream #26581) —
  aggregate throughput via concurrency is where the headroom is.
- **Vision** prefill is slow (mmproj on CPU + image encoding): 18–141 s TTFT, but decode after the
  image is normal (34–40 tok/s) and speculation keeps working.
- **Draft acceptance** 0.53–0.90 depending on task shape; MTP3 avoids the position-4 collapse.

## 7. Stability assertions

- `RestartCount=0`, `OOMKilled=false` across the full suite.
- Zero occurrences of SIGSEGV / allocation failure / `UR_RESULT_ERROR*` / device-lost / GPU hang in
  the server log.

## 8. Operational rules

1. **The B70 containers are production.** Never restart, stop, remove, or rebuild them without
   explicit user consent. Read-only inspection (`docker logs`, `docker inspect`, `docker ps`) is fine.
2. **One GPU, one server.** A second llama.cpp container cannot co-exist with this one on the single
   card (VRAM), so a test image must replace it — not run beside it.
3. **Promote by digest, never by moving a tag by hand** — see the GHCR promote procedure in the
   `gh-credentials-push` skill.
4. **Rollback point**: previous stable digest `sha256:5af1e2290fc53930a5f323ac5d26dd9faa9737109336ecdc18aee085b20ef25b`
   (compute-runtime `26.31.39395.13`, the last pre-driver-bump stable). Roll back by stopping the
   current container and starting one from that digest.
5. Any configuration change gets its own dated entry below, and any superseded document gets a
   `Superseded by …` line at the top.

## 9. Mirrors of this configuration

| File | Role |
|---|---|
| [`examples/qwen27b-server.sh`](../examples/qwen27b-server.sh) | bare-metal launcher mirroring §3 exactly |
| [`docker-compose.yml`](../docker-compose.yml) | container definition mirroring §2 + §3 |
| [`benchmark/configs/golden-v041-q8-128k-mtp3.md`](../benchmark/configs/golden-v041-q8-128k-mtp3.md) | config record with the measured numbers |
| [`LEVEL-ZERO-VERSION-DISCREPANCY.md`](LEVEL-ZERO-VERSION-DISCREPANCY.md) | why the image ships L0 1.28.6 while CI reports 1.32.0 |

## Change log

| Date | Change |
|---|---|
| 2026-09-14 | Golden established: v0.4.1 (`:stable`), q8_0 KV / 128k / MTP3 + Q8_0 draft, reasoning off. Promoted from issue #17 after a full 3-vision + 5-text pass. Replaces the v0.3.0-era "F16 KV + 96k + Q4_0 MTP" recommendation (kept below as history). |
| 2026-09-20 | `:stable` re-pointed to the issue-#18 artifact (compute-runtime `26.35.39758.10`, IGC `v2.41.5`, digest `sha256:d7f30320…`). Image/digest/§6 provenance rows updated to match what production actually serves — they had drifted a release behind. |
| 2026-09-20 | Level Zero recorded as **loader `1.28.6`**, not the `1.32.0` CI reports. The image is built on a base that already ships L0 1.28.6, and the oneAPI install in the same stage displaces the CI-pinned 1.32.0 packages. Driver (`26.35.39758.10`) and IGC (`2.41.5`) are unaffected. Root cause and evidence: [`LEVEL-ZERO-VERSION-DISCREPANCY.md`](LEVEL-ZERO-VERSION-DISCREPANCY.md). |
| 2026-09-20 | Issue #19 dev candidate (`60081bb`, digest `sha256:4dc70c03…`) passed the full battery 8/8 with zero crashes; **not** promoted to `:stable` (parity, no stated reason for the llama.cpp bump). Published as `:server-dev` + `:server-dev-b11046-c26.35.39758.10`. Report: [`benchmark/results/2026-09-20-issue19-b11046-dev.md`](../benchmark/results/2026-09-20-issue19-b11046-dev.md). |
