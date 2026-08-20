# Project Status (Community)

**Focus**: Up-to-date llama.cpp + SYCL Docker for Intel Arc Pro B70 (and other Battlemage B-series).

**Current defaults in Dockerfile** (as of creation):
- Base: intel/deep-learning-essentials devel (2026.1 series target)
- IGC: v2.34.4
- Compute Runtime: 26.18.38308.1
- Level Zero: 1.28.2
- Device arch: bmg-g31 (AOT)
- GGML_SYCL_F16=ON
- All major features left enabled (Flash-Attn, reorder kernels, MTP paths, dynamic backends)

**Known working on**:
- Single B70 for Qwen3/Qwen3.6 ~27B dense models (Q4_K_M and similar)
- Flash Attention enabled
- Speculative/MTP draft models supported by the binary

**Not disabled**:
- No GGML_SYCL_DISABLE_OPT
- Flash Attention available
- Full set of kernels for Q4_K / Q5_K / Q6_K reorder etc.

**How to help**:
- Update pins when Intel releases newer compute-runtime for B70
- Add benchmark data in issues/PRs
- Improve docs for multi-GPU or specific model families

Last updated: $(date -Iseconds)
