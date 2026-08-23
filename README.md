# llama.cpp SYCL for Intel Arc B70 (Community)

**Goal**: A maintained, up-to-date Docker image + guidance for running llama.cpp with SYCL on Intel Arc Pro B70 (32 GB) and other Battlemage cards.

Official `ghcr.io/ggml-org/llama.cpp:* -intel` images often lag on oneAPI / compute-runtime / IGC. This community effort keeps the stack current for B70 while **keeping every feature enabled** (Flash Attention, speculative decoding / MTP, reorder kernels, dynamic backends, etc.). No `GGML_SYCL_DISABLE_OPT`.

## Why a community image for B70?

- B70 (BMG-G31 / Xe2) needs recent Intel Compute Runtime + IGC (26.18+ series recommended in community reports).
- oneAPI base images in the wild are pinned to 2025.x; 2026.x brings better stability and kernels.
- Important runtime flags and build options for B70 are easy to get wrong (device arch for AOT, KV cache type, persistent cache, etc.).
- Flash-Attn and MTP/speculative decoding must stay on — we never disable them.

## Quick start (Docker)

### 1. Build the image (latest components)

```bash
# From this repo root (contains .devops/intel.Dockerfile)
docker build \
  --target server \
  -t llama.cpp-sycl-b70:server \
  -f .devops/intel.Dockerfile \
  --build-arg ONEAPI_VERSION=2026.1.2-devel-ubuntu24.04 \
  --build-arg GGML_SYCL_F16=ON \
  --build-arg GGML_SYCL_DEVICE_ARCH=bmg-g31 \
  .
```

Targets:
- `server` (recommended)
- `light`
- `full`

You can override pins at build time (IGC_VERSION, COMPUTE_RUNTIME_VERSION, etc.) via --build-arg.

### 2. Run on B70

Find your render device:

```bash
ls -l /dev/dri
# Typically /dev/dri/renderD128 or renderD129 for the dGPU
```

Run the server (expose on host):

```bash
docker run --rm -it \
  --device /dev/dri/renderD128:/dev/dri/renderD128 \
  --device /dev/dri/card0:/dev/dri/card0 \
  -v /path/to/models:/models \
  -p 8080:8080 \
  llama.cpp-sycl-b70:server \
  -m /models/Qwen3-27B-Q4_K_M.gguf \
  --n-gpu-layers 999 \
  --ctx-size 131072 \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --flash-attn on \
  --port 8080 --host 0.0.0.0
```

**Critical environment inside the container (or pass via -e):**

```bash
ONEAPI_DEVICE_SELECTOR=level_zero:0
SYCL_CACHE_PERSISTENT=0          # Avoids SIGSEGV on Xe2 during JIT
ZES_ENABLE_SYSMAN=1
# Do NOT set GGML_SYCL_DISABLE_OPT (big perf regression)
```

Example with env:

```bash
docker run ... \
  -e ONEAPI_DEVICE_SELECTOR=level_zero:0 \
  -e SYCL_CACHE_PERSISTENT=0 \
  -e ZES_ENABLE_SYSMAN=1 \
  llama.cpp-sycl-b70:server ...
```

### Recommended launch flags for Qwen3 27B-class on single B70

From community testing (B70 + SYCL):

- `--n-gpu-layers 999` (or very high)
- `--flash-attn on` (or auto). SYCL backend supports it.
- Default KV: f16 safe for short ctx. For MTP + 96k-128k, q8_0 KV is the current recommended lifeline (see benchmark/B70_llamacpp_mtp4_128k_q8_20260821.md)
- `--ctx-size` as large as VRAM allows (many run 24k-32k+)
- For MTP/speculative: use a draft model + `--spec-draft-model` + `--spec-type draft-mtp` (or `-md`) (the binary supports it; nothing is disabled here)

For Qwen3 MTP quants (Unsloth-style etc.), the server binary supports draft models. Test with your specific GGUF.

## docker-compose example

See `docker-compose.yml` in this repo.

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

Then run with the env vars above.

## What we keep enabled (by design)

- Flash Attention (SYCL backend support since ~2026.03)
- Speculative decoding / MTP paths
- Reorder / optimized mul_mat kernels for Q4_K etc.
- Dynamic backends (GGML_BACKEND_DL)
- F16 KV by default (critical for B70)
- Full CPU variant fallbacks

We explicitly do **not** set `GGML_SYCL_DISABLE_OPT`.

## CI / Automatic builds (new split workflow)

We now use **two dedicated workflows**:

| Workflow                  | Branch | Schedule              | What it tracks                              | Behavior |
|---------------------------|--------|-----------------------|---------------------------------------------|----------|
| `build-stable.yml`        | main   | Every 4 hours         | llama.cpp `v*` tags + **all** Intel deps    | Build temp tag if anything changed → open Issue |
| `build-dev.yml`           | dev    | Saturday 00:00 UTC    | llama.cpp + latest deps                     | 2a: if latest llama tag is `v*` → skip + guidance Issue<br>2b: clone the latest `b*` tag + latest deps, build temp tag + open Issue |

**Temporary tags** are created (e.g. `server-v1.XX-YYYYMMDD-HHMM` or `server-dev-...`).

After the workflow opens a GitHub Issue with diffs, **you** (the maintainer) pull & test on the real B70 server. When satisfied, you create a proper release tag (or point `dev`).

### Manual trigger
- Go to Actions → choose `Build Stable` or `Build Dev` → Run workflow.

### Updating pins manually (still supported)
You can still edit `.devops/intel.Dockerfile` and bump versions. The next scheduled run (or manual trigger) will pick up the change if you want CI to validate it.

See the two workflow files for exact logic.

Test matrix we care about:
- Qwen3 / Qwen3.6 27B dense + MTP variants (Q4_K_M, Q5_K etc.)
- Flash-attn on/off impact
- Large context (24k–80k+)
- Multi-GPU split if relevant

## Performance notes (B70)

Community reports (as of mid-2026):
- Vulkan is often fastest for raw speed on some workloads.
- SYCL (this path) frequently wins on generation throughput and stability for long contexts when tuned.
- Use f16 KV. Mixed/dynamic quants can miss optimized paths.
- AOT with `bmg-g31` reduces cold-start JIT cost.

Always benchmark your exact model + quant.

## Contributing

- Open issues with exact `sycl-ls`, `uname -a`, oneAPI version, compute-runtime version, model, and command line.
- PRs that update pins + provide before/after benchmarks on B70 are highly welcome.
- We maintain this as a community overlay focused on Intel Arc B-Series. Upstream changes in ggml-org/llama.cpp are pulled in by rebuilding against fresh source.

## Credits

- Upstream: https://github.com/ggml-org/llama.cpp
- Intel oneAPI / compute-runtime teams
- Community testers on r/LocalLLM, Level1Techs, etc. who shared B70 + SYCL recipes

License: Same as upstream (MIT for the project structure + docs here).

---

**This is a community effort.** Use at your own risk. Test thoroughly with your workloads. Report issues here so we can keep the pins fresh for B70.
