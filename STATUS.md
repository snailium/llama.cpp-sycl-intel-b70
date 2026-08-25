# Project Status

**Focus:** an up-to-date llama.cpp + SYCL Docker image for the Intel Arc Pro B70 (and other Battlemage B-series).

> **Recommended path:** prebuilt `llama.cpp-sycl-b70:server` container (`:stable`) + **MTP4/128k + q8_0 KV + Q8 MTP draft + Q8 mmproj**, on the **v0.3.0 + ubuntu26.04-base** image. Full suite (T1–T5 + V1–V3) verified on the upgrade stack (compute-runtime 26.31), 0 crashes. See `benchmark/` for the full evidence.

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
| Web UI build | `OFF` by default (`BUILD_WEBUI=0`), enabled via `--build-arg BUILD_WEBUI=1` |

**Important build fix:** the oneAPI base image bundles an older IGC (`libigc.so` 2.36.3) in `/usr/lib` that shadows the newer pinned IGC installed to `/usr/local/lib`. The Dockerfile now removes that shadowing `libigc`/`libiga64` (and runs `ldconfig`) in both the build and base stages, so ocloc and the NEO driver load the matching IGC — otherwise every AOT compile fails with `Incompatible interface in IGC: IGC_OCL_DEVC`.

All major features remain enabled: Flash Attention, reorder kernels, MTP / speculative paths, and dynamic backends (`GGML_BACKEND_DL`). **No `GGML_SYCL_DISABLE_OPT`.**

## Verified working on

- Single B70, Qwen3.8-27B (Q4_K_M) + MTP draft + mmproj:
  - **MTP4 + 128k + q8_0 KV, Q8 MTP draft + Q8 mmproj (v0.3.0 + u26 base) — full suite pass** (recommended, upgrade stack).
  - **MTP3 + 128k + q8_0 KV, Q8 MTP draft + Q8 mmproj (v0.2.0) — full suite pass** (prior production, superseded by MTP4).
  - **MTP3 + 96k + q8_0 KV — 5/5 text tasks** (legacy-safe, pre-upgrade).
  - **MTP4 + 128k + q8_0 KV — 5/5 text + 3 vision** (max context, old stack).
  - no-draft + 128k + f16 KV — stable agent workhorse.
- Flash Attention enabled; speculative/MTP drafts supported by the binary.
- `pcie_aspm=off` host flag for PCIe stability (B450).

## Known limitations

- Single-shot speed is 2–3× below vLLM because the SYCL backend has not wired B70's XMX matrix units (upstream TODO). Re-evaluate on each llama.cpp update.
- Vision works (on par with a dual-3060 27B in quality) but is slow — visual-encoding prefill dominates.
- f16 KV + MTP + ≥96k context OOMs; q8_0 KV required for that combination.

## How to help

- Update pins when Intel releases newer compute-runtime/IGC for B70 — the CI workflows will also catch them.
- Add benchmark data in issues/PRs (use `benchmark/METHODOLOGY.md` and add reports under `benchmark/results/`).
- Improve docs for multi-GPU or specific model families.

Last updated: 2026-08-25.