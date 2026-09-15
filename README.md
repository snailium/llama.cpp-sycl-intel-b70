# llama.cpp + SYCL for Intel Arc B70 (Community)

A maintained, up-to-date Docker image + guidance for running **llama.cpp with SYCL** on the **Intel Arc Pro B70 (32 GB, BMG-G31 / Xe2)** and other Battlemage B-series cards.

The official `ghcr.io/ggml-org/llama.cpp:* -intel` images often lag on oneAPI / compute-runtime / IGC. This community effort keeps the stack current for B70 while **keeping every feature enabled** — Flash Attention, speculative decoding / MTP, reorder kernels, and dynamic backends. **No `GGML_SYCL_DISABLE_OPT`.**

## ✨ Highlights

- **First backend that reliably completes a full agent suite on B70.** llama.cpp + SYCL is the only B70 backend verified to pass all five benchmark tasks (T1–T5) in a single run — vLLM-MTP crashes on long agent chains.
- **Golden config verified (v0.4.1, 2026-09-14):** **q8_0 KV / 131072 ctx + MTP3 with a Q8_0 MTP draft + Q8_0 mmproj** on the `:stable` image ≈ **prefill 470–490 t/s / decode 41–46 t/s (short context)** at draft acceptance 0.53–0.90; full suite (T1–T5 + V1–V3) passes, 0 crashes. See [`docs/GOLDEN-CONFIG.md`](./docs/GOLDEN-CONFIG.md).

> **Q8 (not BF16) MTP draft is required at 128k** — the BF16 draft's speculative buffer reserve crashes the 32 GB card; Q8 frees ~1.5 GB with no acceptance loss.
- **q8_0 KV at 128k** is what makes the golden config fit on one card without host-RAM OOM, and (since upstream #25874, merged 2026-08-04) quantized KV still reaches the XMX oneDNN SDPA prefill path via dequantize→f16. The earlier v0.3.0-era recommendation used **F16 KV + 96k** (+1.5 GB headroom) — historical, see `docs/B70-SYCL-KNOWLEDGE.md`.
- **Why it's slower than vLLM, in one line:** the llama.cpp SYCL backend's **default matmul kernels** don't yet use B70's XMX — but the **oneDNN/XMX flash-attention path** (v0.3.0+, `GGML_SYCL_DNN=ON`) **does** (prefill 470–490 t/s). See [`docs/B70-SYCL-KNOWLEDGE.md`](./docs/B70-SYCL-KNOWLEDGE.md) §7.

## Why a community image for B70?

- B70 (BMG-G31 / Xe2) needs a recent Intel Compute Runtime + IGC.
- OneAPI base images in the wild are pinned to 2025.x; 2026.x brings better stability and kernels.
- B70-specific build/runtime flags are easy to get wrong (device arch for AOT, KV cache type, persistent cache).
- Flash-Attn and MTP/speculative decoding must stay **on** — we never disable them.

## Quick start (Docker)

### 1. Build the image

From the repo root (contains `.devops/intel.Dockerfile`):

```bash
# Convenience script
./scripts/build-b70-image.sh server

# ...or directly
docker build \
  --target server \
  -t llama.cpp-sycl-b70:server \
  -f .devops/intel.Dockerfile \
  --build-arg ONEAPI_VERSION=2026.1.2-devel-ubuntu26.04 \
  --build-arg GGML_SYCL_F16=ON \
  --build-arg GGML_SYCL_DEVICE_ARCH=bmg-g31 \
  .
```

Build targets: `server` (recommended), `light`, `full`. Override any Intel dependency pin at build time via `--build-arg` (`IGC_VERSION`, `COMPUTE_RUNTIME_VERSION`, `LEVEL_ZERO_VERSION`, …).

> **DNN / XMX:** the image built above is **oneDNN-enabled** — the Dockerfile installs
> `intel-oneapi-dnnl-devel` (build) + `intel-oneapi-dnnl` (runtime) and configures
> `-DGGML_SYCL_DNN=ON` (default ON for llama.cpp v0.3.0). This unlocks the **XMX**
> flash-attention SDPA path on the B70 (deep-context prefill ≈2×, up to 4–5×).
> To use it at runtime set `GGML_SYCL_FA_ONEDNN=1` **and** use **F16 KV**
> `--cache-type-k/v f16`, see §Run) — XMX SDPA only fires on native F16, BF16 is
> explicitly excluded by the oneDNN kernel.
>
> **After a build-config change** (e.g. base image, oneDNN, or any Dockerfile edit):
> the GHCR dedup fingerprint (`server-c<CR>-<llama>-`) does **not** include build
> config, so CI treats the current combo as already built and skips it. Run the
> **Build Stable** workflow from the **Actions** UI with **`force: true`** to rebuild
> this combo under the new config (the fresh candidate then satisfies dedup).

### 2. Run on B70

Find your render device first:

```bash
ls -l /dev/dri          # typically /dev/dri/renderD128 or renderD129 for the dGPU
```

Docker run (**this is the golden production configuration** — full rationale, image digest and measured baseline in [`docs/GOLDEN-CONFIG.md`](./docs/GOLDEN-CONFIG.md)):

```bash
docker run -d --name b70-llama \
  --device /dev/dri \
  -v /path/to/models:/models:ro \
  -p 18082:8080 \
  -e ONEAPI_DEVICE_SELECTOR=level_zero:0 \
  -e SYCL_CACHE_PERSISTENT=0 \
  -e ZES_ENABLE_SYSMAN=1 \
  --restart no \
  ghcr.io/snailium/llama.cpp-sycl-intel-b70/llama-sycl-b70:stable \
  -m /models/Qwen3.8-27B-Q4_K_M.gguf \
  --mmproj /models/mmproj-Qwen3.8-27B-Q8_0.gguf --no-mmproj-offload --image-min-tokens 1024 \
  --n-gpu-layers 999 \
  --ctx-size 131072 \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --flash-attn on \
  --spec-draft-model /models/mtp-Qwen3.8-27B-Q8_0.gguf \
  --spec-type draft-mtp --spec-draft-n-max 3 --spec-draft-p-min 0.1 \
  --spec-draft-type-k q8_0 --spec-draft-type-v q8_0 \
  --reasoning off \
  --chat-template-kwargs '{"enable_thinking":false,"preserve_thinking":false}' \
  --port 8080 --host 0.0.0.0
```

Model load takes ~2 minutes; `/health` returns 503 ("Loading model") until then — poll `/v1/models` instead.

**Mandatory environment (never set `GGML_SYCL_DISABLE_OPT`):**

```bash
ONEAPI_DEVICE_SELECTOR=level_zero:0   # select the GPU
SYCL_CACHE_PERSISTENT=0               # =1 SIGSEGVs on Xe2 during first JIT
ZES_ENABLE_SYSMAN=1
```

A `docker-compose.yml` and a ready-made launcher for the Qwen3.8-27B MTP stack are included (`examples/qwen27b-server.sh`).

### Recommended configuration for Qwen3 27B-class on a single B70

| Config | Context | KV | MTP draft | When |
|--------|---------|----|-----------|------|
| **MTP3 + q8_0/128k — GOLDEN, current production** | 131072 | **q8_0** | **Q8_0 MTP, n=3** | Default. v0.4.1 `:stable`, oneDNN/XMX; full suite pass 2026-09-14 |
| MTP3 + q8_0/128k (v0.4.0) | 131072 | q8_0 | Q8_0 MTP, n=3 | Prior production; on par with v0.4.1 |
| MTP3 + f16/96k + Q4_0 draft (v0.3.0 + oneDNN/XMX) | 98304 | f16 | Q4_0 MTP, n=3 | Earlier recommendation; native (no-dequant) XMX path, ~1.5 GB VRAM margin |
| MTP4 + q8_0/128k | 131072 | q8_0 | Q8_0 MTP, n=4 | Only for short one-shot generation — position-4 acceptance collapses on agent workloads |
| MTP3 + 96k (legacy) | 98304 | q8_0 | BF16 MTP, n=3 | Pre-upgrade safe config |
| no-draft + 128k | 131072 | f16 | none | The stable agent "workhorse" when speculation isn't worth it |

Full details, memory footprints and measured numbers in [`benchmark/configs/`](./benchmark/configs/); the golden config record is [`benchmark/configs/golden-v041-q8-128k-mtp3.md`](./benchmark/configs/golden-v041-q8-128k-mtp3.md). Also:

- `--n-gpu-layers 999` (offload everything).
- `--flash-attn on` (SYCL backend supports it).
- **q8_0 KV is what makes MTP + a full 128k window fit on one card** (f16 KV at that size plus a speculative draft exhausts 32 GB). f16 KV is the native, no-dequant path for the oneDNN SDPA kernel and is fine at ≤96k.
- **Use a high-quality MTP draft (Q8_0)** — a low-acceptance 2B draft is a net slowdown.
- **Turn thinking off at both layers**: `--reasoning off` plus `--chat-template-kwargs '{"enable_thinking":false,"preserve_thinking":false}'`.

### Recommended sampling parameters for Qwen3.8-27B (official, 2026-08)

Source: the official **Qwen3.8-27B HF model card** (`Recommended Inference Parameters`). Two modes:

| Mode | temperature | top_p | top_k | min_p | presence_penalty | repetition_penalty |
|------|------------|-------|-------|-------|------------------|--------------------|
| **Thinking** | 1.0 | 0.95 | 20 | 0.0 | 0.0 | 1.0 |
| **Instruct (non-thinking) — use for agents** | **0.7** | **0.80** | **20** | **0.0** | **1.5** | **1.0** |

> **The textbook fix for Qwen3.8 verbosity/rambling in non-thinking mode is `presence_penalty=1.5`** (penalizes already-seen tokens), *not* a manually-lowered temperature. With `--temp 0.7 --top-p 0.80 --top-k 20 --min-p 0.0 --presence-penalty 1.5 --frequency-penalty 0.0 --repeat-penalty 1.0` the model answers crisply with no thinking leakage into the visible channel and intact function-calling.

Add these to the `llama-server` invocation when serving Qwen3.8-27B in non-thinking mode (verify with `GET /v1/... /props` → `default_generation_settings.params`):

```bash
--temp 0.7 --top-p 0.80 --top-k 20 --min-p 0.0 \
--presence-penalty 1.5 --frequency-penalty 0.0 --repeat-penalty 1.0
```

**Chat template note:** the GGUF bakes in the official native Qwen3.8-27B template (8952 chars, full `enable_thinking` / `reasoning_effort` VL + XML tool logic). A log line like `Using specialized template: Qwen3-Coder` is just llama.cpp's name for the `arch=qwen35` built-in — the in-GGUF template is loaded in preference (`example_format: '<|im_start|>system`). Disable thinking per-request with `chat_template_kwargs.enable_thinking:false` (or `reasoning_effort:"none"`); a bare top-level `enable_thinking` is ignored by this build.

## Project structure

```
.
├── README.md                   ← you are here
├── STATUS.md                   ← current pin versions & known-working state
├── CONTRIBUTING.md             ← how to contribute (benchmarks welcome)
├── docs/
│   ├── B70-SYCL-KNOWLEDGE.md   ← all field knowledge & the "why" behind the config
│   └── B70-TUNING.md           ← hands-on flags, pitfalls, PCIe stability
├── benchmark/
│   ├── METHODOLOGY.md          ← the 5-task test suite + metric definitions
│   ├── configs/                ← one file per reproducible server config
│   ├── results/                ← one file per dated test run
│   └── incidents/              ← stability / dropout incident logs
├── examples/
│   └── qwen27b-server.sh       ← recommended launcher (Q4 MTP + Q8 mmproj, MTP3/96k + XMX)
├── scripts/
│   └── build-b70-image.sh      ← convenience build script
├── .devops/intel.Dockerfile    ← the build pipeline (all version pins)
├── docker-compose.yml
├── .github/workflows/          ← CI auto-build (stable / dev)
└── llama.cpp/                  ← upstream llama.cpp vendored via git subtree
```

## What we keep enabled (by design)

- **Flash Attention** (SYCL support since ~2026.03).
- **Speculative decoding / MTP** paths.
- Reorder / optimized `mul_mat` kernels for Q4_K etc.
- **Dynamic backends** (`GGML_BACKEND_DL`).
- F16 KV for short contexts (q8_0 for MTP + large context).
- Full CPU-variant fallbacks.

We explicitly do **not** set `GGML_SYCL_DISABLE_OPT`.

## Benchmarks

`benchmark/` holds the full test methodology and all measured runs. **Start with [`benchmark/METHODOLOGY.md`](./benchmark/METHODOLOGY.md)** for the 5-task suite and metric conventions, then browse:

- **[configs/](./benchmark/configs/)** — reproducible server configurations.
- **[results/](./benchmark/results/)** — dated run reports (the **recommended/current** result is `2026-08-25-v030-f16-96k-dnn-mtp3-q4.md`; the Q8 tagging-gate is `2026-08-25-mtp3-q8-128k.md`).
- **[incidents/](./benchmark/incidents/)** — the B70 PCIe-dropout incident log.

> **Testing methodology matters.** Always verify cards with a real `/v1/chat/completions` → `finish_reason=stop`, keep thinking **off** for artifact tasks, use q8_0 KV for MTP+large context, and never trust llama.cpp's batched `eval time` figures as the real throughput (see methodology).

## Building from source (bare metal, for comparison)

```bash
source /opt/intel/oneapi/setvars.sh
# oneDNN/libdnnl is required for the XMX SDPA path (GGML_SYCL_DNN=ON):
#   apt-get install intel-oneapi-dnnl-devel   (Intel oneAPI repo)  OR  libdnnl-dev
cmake -B build \
  -DGGML_SYCL=ON \
  -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx \
  -DGGML_SYCL_DEVICE_ARCH=bmg-g31 \
  -DGGML_SYCL_F16=ON \
  -DGGML_SYCL_DNN=ON \
  -DDNNL_ROOT=/opt/intel/oneapi/dnnl/latest \
  -DGGML_BACKEND_DL=ON
cmake --build build --config Release -j$(nproc)
```

Then run with the env vars above. `GGML_SYCL_DNN=ON` enables the oneDNN/XMX
flash-attention path (run with `GGML_SYCL_FA_ONEDNN=1` + F16 KV). **Note:** a
bare-metal build may hit the Intel driver "version triangle" and fail to initialize
at runtime — the prebuilt container is the reliable path (see `docs/B70-SYCL-KNOWLEDGE.md` §2).

## Performance notes (B70)

- **llama.cpp + SYCL (this path)** is the throughput/stability choice for long contexts and **agent workloads** once tuned.
- It is **2–3× slower than vLLM** on raw single-shot speed because the SYCL backend has not wired B70's XMX matrix units yet — an upstream TODO (`SYCL_USE_XMX` is a misnomer). Recheck on each llama.cpp update.
- **AOT with `bmg-g31`** sharply reduces cold-start JIT cost / SIGSEGV risk.
- Always benchmark your exact model + quant. Batch/aggregate throughput, not just single-stream decode, is where B70 shines.

See `benchmark/` for measured numbers.

## CI / Automatic builds

Two dedicated workflows keep pins fresh without manual work:

| Workflow | Branch | Schedule | What it tracks |
|----------|--------|----------|----------------|
| `build-stable.yml` | `main` | Every 4 hours | llama.cpp `v*` tags + **all** Intel deps (compute-runtime, IGC, Level Zero, oneAPI base) |
| `build-dev.yml` | `dev` | Saturdays 00:00 UTC | llama.cpp + latest deps (skips when the newest tag is a release, else builds latest `b*`) |

When a change is detected, CI builds a **temporary tag** (`server-vX.Y-YYYYMMDD-HHMM` / `server-dev-…`) and opens a GitHub Issue with diffs. The maintainer then pulls it to real B70 hardware, tests, and only then creates a proper named tag. Manual pins in the Dockerfile are still supported.

## Contributing

Contributions that keep the B-series current and high-performance are very welcome — see [`CONTRIBUTING.md`](./CONTRIBUTING.md). Especially valuable: verified version-pin updates and before/after **benchmarks on real B70 hardware**.

## License & credits

- License: same as upstream — MIT for the project structure and docs here.
- Upstream: [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)
- Intel oneAPI / compute-runtime teams.
- Community testers on r/LocalLLM, Level1Techs, etc. who shared B70 + SYCL recipes.

---

**This is a community effort.** Use at your own risk. Test thoroughly with your workloads and report issues so the pins stay fresh for B70.