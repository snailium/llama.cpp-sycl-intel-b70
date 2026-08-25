# llama.cpp + SYCL for Intel Arc B70 (Community)

A maintained, up-to-date Docker image + guidance for running **llama.cpp with SYCL** on the **Intel Arc Pro B70 (32 GB, BMG-G31 / Xe2)** and other Battlemage B-series cards.

The official `ghcr.io/ggml-org/llama.cpp:* -intel` images often lag on oneAPI / compute-runtime / IGC. This community effort keeps the stack current for B70 while **keeping every feature enabled** — Flash Attention, speculative decoding / MTP, reorder kernels, and dynamic backends. **No `GGML_SYCL_DISABLE_OPT`.**

## ✨ Highlights

- **First backend that reliably completes a full agent suite on B70.** llama.cpp + SYCL is the only B70 backend verified to pass all five benchmark tasks (T1–T5) in a single run — vLLM-MTP crashes on long agent chains.
- **Recommended config verified:** **MTP4 + 128k + q8_0 KV, Q8 MTP draft + Q8 mmproj** on the **v0.3.0 + ubuntu26.04-base** image ≈ **25–42 t/s** direct decode, draft acceptance 0.57 (on par with MTP3). Full suite (T1–T5 + V1–V3) passes on the upgrade stack (`:stable`), 0 crashes.

> **Q8 (not BF16) MTP draft is required on the upgrade stack at 128k** — the BF16 draft's speculative buffer reserve crashes the 32 GB card; Q8 frees ~1.5 GB with no acceptance loss.
- **q8_0 KV is the stability lifeline** — the fix that makes MTP + large context fit in 32 GB without host-RAM OOM.
- **Why it's slower than vLLM, in one line:** the llama.cpp SYCL backend does not yet use B70's XMX matrix units (source-confirmed). See [`docs/B70-SYCL-KNOWLEDGE.md`](./docs/B70-SYCL-KNOWLEDGE.md).

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

### 2. Run on B70

Find your render device first:

```bash
ls -l /dev/dri          # typically /dev/dri/renderD128 or renderD129 for the dGPU
```

Docker run (with the mandatory environment inside or via `-e`):

```bash
docker run --rm -it \
  --device /dev/dri \
  -v /path/to/models:/models \
  -p 8080:8080 \
  -e ONEAPI_DEVICE_SELECTOR=level_zero:0 \
  -e SYCL_CACHE_PERSISTENT=0 \
  -e ZES_ENABLE_SYSMAN=1 \
  llama.cpp-sycl-b70:server \
  -m /models/Qwen3.8-27B-Q4_K_M.gguf \
  --n-gpu-layers 999 \
  --flash-attn on \
  --ctx-size 98304 \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --port 8080 --host 0.0.0.0
```

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
| **MTP4 + Q8/128k** (recommended) | 128k | **q8_0** | **Q8_0 MTP, n=4** | Default / production (v0.3.0 + u26 base, upgrade stack) |
| MTP3 + Q8/128k (v0.2.0) | 128k | **q8_0** | Q8_0 MTP, n=3 | Prior production (superseded by MTP4) |
| MTP3 + 96k (legacy) | 96k | **q8_0** | BF16 MTP, n=3 | Pre-upgrade safe config |
| MTP4 + 128k (max, old stack) | 128k | **q8_0** | BF16 MTP, n=4 | When the full 128k window was required pre-upgrade |
| no-draft + 128k | 128k | f16 | none | The stable agent "workhorse" when speculation isn't worth it |

Full details and memory footprints in [`benchmark/configs/`](./benchmark/configs/). Also:

- `--n-gpu-layers 999` (offload everything).
- `--flash-attn on` (SYCL backend supports it).
- **q8_0 KV** is required for MTP + 96k–128k (f16 KV + MTP + large ctx OOMs). f16 KV is fine for short contexts.
- **Use a high-quality MTP draft (Q8_0 on the upgrade stack; BF16 on the old stack)** — a low-acceptance 2B draft is a net slowdown.

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
│   └── qwen27b-server.sh       ← recommended launcher (Q8 MTP + Q8 mmproj, MTP4/128k)
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
- **[results/](./benchmark/results/)** — dated run reports (the **recommended/current** result is `2026-08-25-v030-u26-mtp4-q8.md`; the Q8 tagging-gate is `2026-08-25-mtp3-q8-128k.md`).
- **[incidents/](./benchmark/incidents/)** — the B70 PCIe-dropout incident log.

> **Testing methodology matters.** Always verify cards with a real `/v1/chat/completions` → `finish_reason=stop`, keep thinking **off** for artifact tasks, use q8_0 KV for MTP+large context, and never trust llama.cpp's batched `eval time` figures as the real throughput (see methodology).

## Building from source (bare metal, for comparison)

```bash
source /opt/intel/oneapi/setvars.sh
cmake -B build \
  -DGGML_SYCL=ON \
  -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx \
  -DGGML_SYCL_DEVICE_ARCH=bmg-g31 \
  -DGGML_SYCL_F16=ON \
  -DGGML_BACKEND_DL=ON
cmake --build build --config Release -j$(nproc)
```

Then run with the env vars above. **Note:** a bare-metal build may hit the Intel driver "version triangle" and fail to initialize at runtime — the prebuilt container is the reliable path (see `docs/B70-SYCL-KNOWLEDGE.md` §2).

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