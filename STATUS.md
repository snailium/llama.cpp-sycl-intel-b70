# Project Status

**Focus:** an up-to-date llama.cpp + SYCL Docker image for the Intel Arc Pro B70 (and other Battlemage B-series).

> **Golden configuration (current production, as of 2026-09-24):** prebuilt
> `llama.cpp-sycl-b70:stable` image (llama.cpp **v0.5.0**, compute-runtime 26.35.39758.10,
> IGC v2.41.5, Level Zero loader 1.32.0, oneDNN/XMX build) + **q8_0 KV / 131072 ctx + MTP3 with a
> Q8_0 MTP draft + Q8_0 mmproj**, `--reasoning off` and template-level `enable_thinking:false`,
> official Qwen non-thinking sampling.
> Full suite (T1–T5 + V1–V3) verified **twice on the same digest**: **0 crashes**, text prefill
> 440–530 tok/s, decode 40–45 tok/s short-context / ~21 tok/s deep-context, draft acceptance 0.49–0.88.
>
> **Canonical description and image digest: [`docs/GOLDEN-CONFIG.md`](docs/GOLDEN-CONFIG.md).**
> Evidence: [`2026-09-23-issue21-v050-stable.md`](benchmark/results/2026-09-23-issue21-v050-stable.md)
> and [`…-retest.md`](benchmark/results/2026-09-23-issue21-v050-retest.md).
> Previous stable (rollback point): v0.4.1, digest `sha256:d7f30320…`.
> Mirrors: [`examples/qwen27b-server.sh`](examples/qwen27b-server.sh), [`docker-compose.yml`](docker-compose.yml).

## Current default pins in `.devops/intel.Dockerfile`

These track the latest `intel/compute-runtime` release and its **documented paired** components (the compute-runtime release notes list the exact IGC / Level Zero / gmmlib used to build it). CI derives the whole set from compute-runtime automatically.

| Component | Version |
|-----------|---------|
| Base image | `intel/deep-learning-essentials:2026.1.2-devel-ubuntu26.04` |
| IGC | `v2.40.13` |
| Compute Runtime | `26.31.39395.13` |
| Level Zero | `1.32.0` |
| igdgmm | `22.10.0` |
| Device arch | `bmg-g31` (AOT) |
| GGML_SYCL_F16 | `ON` |
| GGML_SYCL_DNN (oneDNN / XMX SDPA) | `ON` |
| Web UI build | `OFF` by default (`BUILD_WEBUI=0`), enabled via `--build-arg BUILD_WEBUI=1` |

**Important build fix:** the oneAPI base image bundles an older IGC (`libigc.so` 2.36.3) in `/usr/lib` that shadows the newer pinned IGC installed to `/usr/local/lib`. The Dockerfile now removes that shadowing `libigc`/`libiga64` (and runs `ldconfig`) in both the build and base stages, so ocloc and the NEO driver load the matching IGC — otherwise every AOT compile fails with `Incompatible interface in IGC: IGC_OCL_DEVC`.

All major features remain enabled: Flash Attention, reorder kernels, MTP / speculative paths, and dynamic backends (`GGML_BACKEND_DL`). **No `GGML_SYCL_DISABLE_OPT`.**

## Verified working on

- Single B70, Qwen3.8-27B (Q4_K_M) + MTP draft + mmproj:
  - **MTP3 + 128k + q8_0 KV, Q8_0 MTP draft + Q8_0 mmproj — v0.4.1 full suite pass (GOLDEN, current production)**; text prefill 470–490 tok/s, decode 41–46 tok/s short-context, draft acc 0.53–0.90.
  - **MTP3 + 128k + q8_0 KV, Q8_0 MTP draft — v0.4.0 full suite pass** (prior production, on par with v0.4.1).
  - MTP3 + 96k + f16 KV, Q4_0 MTP draft + Q8 mmproj (v0.3.0 + oneDNN/XMX) — full suite pass; superseded by the golden config.
  - MTP3 + 96k + q8_0 KV (legacy-safe, pre-upgrade) and MTP4 + 128k + q8_0 KV (max context, old stack) — 5/5 text + 3 vision.
  - no-draft + 128k + f16 KV — the stable agent "workhorse" when speculation isn't worth it.
- **Official Qwen3.8-27B sampling (instruct/non-thinking)** verified: `--temp 0.7 --top-p 0.80 --top-k 20 --min-p 0.0 --presence-penalty 1.5 --frequency-penalty 0.0 --repeat-penalty 1.0` — crisp output, no thinking leakage into the visible channel, function-calling intact. (Qwen's textbook fix for verbosity = `presence_penalty=1.5`, not low temperature. See README §"Recommended sampling parameters".)
- **Thinking off requires both layers**: `--reasoning off` (response parsing) *and* the template-level default from `--chat-template-kwargs '{"enable_thinking":false,"preserve_thinking":false}'`.
- Flash Attention enabled; speculative/MTP drafts supported by the binary.
- `pcie_aspm=off` host flag for PCIe stability (B450).

## Known limitations

- **Decode is memory-latency-bound on Xe2.** Single-stream token generation is ~40–46 tok/s at short context and ~21 tok/s at deep context; the excess cost is a near-constant ~21–25 ns per KV position per full-attention layer per token, and it is identical on Vulkan and SYCL (upstream issue #26581). Concurrency, not a single stream, is where aggregate throughput scales.
- **The SYCL matmul path still does not use B70's XMX matrix units** (upstream code TODO; `SYCL_USE_XMX` is a misleading name). The XMX gains we do get come from the oneDNN SDPA flash-attention path — which covers prefill, not the matmul decode path. Re-evaluate on each llama.cpp update; see the SYCL performance tracking notes.
- **Quantized-KV XMX**: since upstream #25874 (merged 2026-08-04) non-f16 KV (Q4_0/Q4_1/Q5_0/Q5_1/Q8_0/F32) also runs through oneDNN SDPA, via dequantize→f16 at prefill lengths. BF16 and IQ* KV remain excluded.
- f16 KV + MTP + ≥96k context OOMs on a single card; q8_0 KV (or a smaller context) is required for that combination.
- Vision works (quality on par with the earlier dual-GPU baseline) but is slow: image prefill runs at 30–60 tok/s, so TTFT can reach 110–141 s for a large image.
- Only one GPU container can run at a time on the single card — a candidate image must replace the serving container, not run beside it.

## How to help

- Update pins when Intel releases a newer compute-runtime/IGC for B70 — the CI workflows catch them automatically.
- Add benchmark data in issues/PRs (use `benchmark/METHODOLOGY.md`, put reports under `benchmark/results/`).
- Improve docs for multi-GPU or specific model families.

Last updated: 2026-09-24 (llama.cpp v0.5.0 promoted to `:stable` from issue #21).
