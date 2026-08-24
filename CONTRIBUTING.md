# Contributing to llama.cpp + SYCL for Intel Arc B70

We welcome contributions that keep the Intel Arc B-Series (especially B70) current and high-performance while **keeping all features enabled**.

## What we value

- Updated pins for oneAPI, compute-runtime, IGC, and Level Zero **verified on real B70 hardware**.
- Clear **before/after benchmarks** (prompt processing + token generation) for 27B-class models (Qwen3 / Qwen3.8 etc.) with Flash Attention and MTP where applicable — see [`benchmark/METHODOLOGY.md`](./benchmark/METHODOLOGY.md) for the task suite and metric conventions, and add reports under `benchmark/results/`.
- Fixes or docs that do **not** require disabling `GGML_SYCL_DISABLE_OPT`, Flash Attention, or speculative decoding.
- Reproduction steps that include:
  - `sycl-ls` output
  - `uname -a`
  - Exact oneAPI / compute-runtime versions
  - Full command line + model quant

## How to propose a change

1. Fork or clone this repo.
2. Update `.devops/intel.Dockerfile` (or docs) with new versions + rationale.
3. **Test on real B70 if possible** (highly recommended for dependency bumps).
4. Open a PR with:
   - A summary of the change.
   - Benchmark numbers (pp / tg for a 27B model, and an agent-suite run if relevant).
   - Verification that Flash Attention and MTP paths still work.

**Note on CI:** the repository uses two workflows (`build-stable.yml` on `main`, `build-dev.yml` on `dev`) that auto-detect updates to llama.cpp and all Intel dependencies. They build a temporary tag and open a GitHub Issue with diffs; the maintainer tests on real hardware before creating a final tag. You generally do **not** need to trigger builds manually for pin updates — but PRs with local B70 benchmark results are always welcome.

## Scope

This repo focuses on the Docker image and B70-specific tuning. For changes to the core SYCL backend, contribute directly to [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) — the improvement is picked up on the next rebuild.

Thanks for helping keep B70 usable for the latest 27B+ models!