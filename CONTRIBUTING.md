# Contributing to llama.cpp SYCL for Intel Arc B70 (Community)

We welcome contributions that keep the Intel Arc B-Series (especially B70) experience current and high-performance while **keeping all features enabled**.

## What we value

- Updated pins for oneAPI, compute-runtime, IGC, Level Zero that are verified on real B70 hardware.
- Clear before/after benchmarks (prompt processing + token generation) for 27B-class models (Qwen3/Qwen3.6 etc.) with Flash Attention and MTP where applicable.
- Fixes or docs that do **not** require disabling `GGML_SYCL_DISABLE_OPT`, Flash Attention, or speculative decoding.
- Reproduction steps that include:
  - `sycl-ls` output
  - `uname -a`
  - Exact oneAPI / compute-runtime versions
  - Full command line + model quant

## How to propose a change

1. Fork or clone this repo.
2. Update `.devops/intel.Dockerfile` (or docs) with new versions + rationale.
3. Test on real B70 if possible (highly recommended for dep bumps).
4. Open a PR with:
   - Summary of the change
   - Benchmark numbers (pp512 / tg128 or similar for a 27B model)
   - Verification that Flash Attention and MTP paths still work

**Note on CI**: The repository uses two separate GitHub workflows (`build-stable.yml` and `build-dev.yml`). They automatically detect updates to llama.cpp and all Intel dependencies (compute-runtime, IGC, Level Zero, oneAPI base). When they build, they create temporary tags and open a GitHub Issue with diffs. The maintainer then tests on real hardware before creating final tags.

You do **not** need to manually trigger builds for most pin updates — the scheduled workflows will catch them. However, PRs that include local benchmark results on B70 are still very welcome.

## Scope

This repo focuses on the Docker image and B70-specific tuning. For changes to the core SYCL backend, please contribute directly to https://github.com/ggml-org/llama.cpp (and we will pick up the improvement on next rebuild).

Thanks for helping keep B70 usable for the latest 27B+ models!