# llama.cpp + SYCL on Intel Arc Pro B70 — Field Notes (2026-08)

This document consolidates everything learned while deploying, debugging, and measuring llama.cpp + SYCL on the Intel Arc Pro B70. It is the "why" behind the recommended configuration; for hands-on flags see [`B70-TUNING.md`](./B70-TUNING.md) and for test numbers see [`benchmark/`](../benchmark/README.md).

## Bottom line (as of 2026-08)

- **Use the prebuilt container** `llama.cpp-sycl-b70:server`. Do **not** build llama.cpp from source for B70 — the Intel driver "version triangle" (below) makes a self-built runtime fail to initialize.
- **Recommended config:** **MTP4** + **128K** + **KV q8_0** + **Q8 MTP draft + Q8 mmproj** on the **v0.3.0 + ubuntu26.04-base** image — full-suite (T1–T5 + V1–V3) pass on the upgrade stack (`:stable`), 0 crashes. Legacy-safe 96k (BF16 draft) validated pre-upgrade.
- **Q8 draft insight (upgrade stack):** at 128k/context the **BF16 MTP draft crashes** (`Failed to allocate physical memory` — its speculative buffer reserve exceeds the 32 GB card). Quantizing the draft to **Q8_0** frees ~1.5 GB and restores 128k with no acceptance loss (0.567 vs 0.5670).
- **MTP crash insight (upgrade stack):** the 128k/context crash is the **draft model's speculative buffer reserve** (`phys.emplace` → `Failed to allocate physical memory`), not the KV cache — fix it by **quantizing the draft to Q8_0** (frees ~1.5 GB, acceptance unchanged). Separately, **f16 KV** OOMs at MTP + large context — fix that with **q8_0 KV**.
- **Card dropout:** caused by **PCIe ASPM** → add `pcie_aspm=off` and use the physical recovery sequence (below).
- **llama.cpp is ~2–3× slower than vLLM** because the SYCL backend **does not actually use B70's XMX** (confirmed in source, see below).

## 1. Recommended deployment

Use the prebuilt container:

```bash
docker run -d \
  --name b70-qwen27b \
  --device /dev/dri \
  -v /models:/models:ro \
  -p 18080:8080 \
  -e ONEAPI_DEVICE_SELECTOR=level_zero:0 \
  -e SYCL_CACHE_PERSISTENT=0 \
  -e ZES_ENABLE_SYSMAN=1 \
  --entrypoint /app/llama-server \
  llama.cpp-sycl-b70:stable \
  -m /models/Qwen3.8-27B-Q4_K_M.gguf \
  --mmproj /models/mmproj-Qwen3.8-27B-Q8_0.gguf \
  --spec-draft-model /models/mtp-Qwen3.8-27B-Q8_0.gguf \
  --spec-type draft-mtp --spec-draft-n-max 3 --spec-draft-p-min 0.1 \
  ...other flags
```

Also pass `/dev/dri` (or the specific render device) so Level Zero can see the GPU.

**Routes that do NOT work** (all failed in testing):
- Building upstream llama.cpp with oneAPI 2026.1 yourself → `ggml_sycl_init` failure + NEO assertion.
- IPEX-LLM container / Portable Zip → driver version-triangle mismatch (libze_loader ABI problem).
- Manually adding the Intel GPU apt source → key returns 403, or the driver does not recognize B70.

## 2. The version triangle (why prebuilt only)

B70 needs three components to be mutually locked:

| Component | Required version |
|-----------|------------------|
| B70 driver | libze_intel_gpu **1.15.39122** |
| Driver's loader | libze_loader **1.32** (ur ABI 0.12) |
| Old official portable (2025-07) | older loader ~1.18.5 (ABI 0.10) |

Only a container that pins ur 0.12 + libsycl + ze 1.32 + driver 1.15.39122 together can drive B70. Individual pieces pulled from the ecosystem won't line up.

## 3. Mandatory runtime environment

```bash
export ONEAPI_DEVICE_SELECTOR=level_zero:0
export SYCL_CACHE_PERSISTENT=0     # MUST be 0; =1 SIGSEGVs on Xe2 during JIT
export ZES_ENABLE_SYSMAN=1
```

## 4. Final recommended launch flags

**Recommended (MTP4 + 128k + q8_0, Q8 MTP draft + Q8 mmproj; v0.3.0 + ubuntu26.04 base):**

```bash
--ctx-size 131072 \
--cache-type-k q8_0 --cache-type-v q8_0 \
--flash-attn on \
--mmproj /models/mmproj-Qwen3.8-27B-Q8_0.gguf \
--no-mmproj-offload --image-min-tokens 1024 \
--spec-type draft-mtp \
--spec-draft-model /models/mtp-Qwen3.8-27B-Q8_0.gguf \
--spec-draft-n-max 4 \
--spec-draft-p-min 0.1 \
--n-gpu-layers 999
```

> **Q8 MTP draft is required on the upgrade stack (`:stable`, compute-runtime 26.31) at 128k/context.** The BF16 draft's speculative buffer reserve crashes the 32 GB card; Q8 frees ~1.5 GB and restores 128k with no acceptance loss (0.567 vs 0.5670). Legacy-safe 96k (BF16 draft) still works on the old stack — see `benchmark/configs/mtp3-96k.md`.

**Model stack:** use all ggml-org quants (Q4_K_M main + Q8_0 mmproj + Q8_0 MTP draft). See `examples/qwen27b-server.sh`.

## 5. MTP tuning notes

- **A low-quality draft is a net drag.** A 2B draft with acceptance 0.31–0.50 makes generation *slower*; a high-quality **BF16 MTP** draft (acceptance 0.57–0.91) genuinely speeds short tasks +30–60%.
- Higher `n-max` pressures KV harder. `n-max=4` + f16 KV essentially guarantees a T4 OOM.
- `p-min 0.1` is a good neutral start for MTP4.
- Real speed must be read from the client's streamed `tg` or `timings`; llama.cpp's logged `eval time` token/s is inflated by speculative batching.

## 6. Memory & stability core

- **q8_0 KV is the lifeline for MTP + large context.** With f16 KV, the 5.9 GB MTP draft crowds out KV headroom and long agent chains OOM host RAM.
- **Host RAM is the more dangerous limit** than VRAM (observed up to 26 GB+ peak + swap).
- `failed to fit params... n_gpu_layers 999` is a common, non-fatal warning.
- Dropouts are almost always **PCIe ASPM** → `pcie_aspm=off` in the kernel cmdline resolves recurrence.
- After a dropout, recovery **must be physical**: remove card → boot on iGPU → shut down → reinsert card → boot.

## 7. The XMX reality (why llama.cpp is slower)

The llama.cpp SYCL backend **does not actually use B70's XMX** matrix units yet. Source evidence in `ggml-sycl/common.hpp`:

```cpp
// define for XMX in Intel GPU
// TODO: currently, it's not used for XMX really.
#if !defined(GGML_SYCL_FORCE_MMQ)
    #define SYCL_USE_XMX
#endif
```

`SYCL_USE_XMX` only selects MMQ vs DMMV kernels — it is **not** a real DPAS/XMX invocation. This is the main reason llama.cpp is 2–3× slower than vLLM (which uses a dedicated XPU XMX kernel path). Worth re-checking as upstream matures (see `benchmark/results/2026-08-21-mtp4-128k.md` §IV for the vLLM comparison).

## 8. Monitoring & debugging

```bash
# xpu-smi background monitor
nohup bash -c 'while true; do echo "=== $(date)"; xpu-smi stats -d 0; sleep 5; done' > ~/xpu-smi-monitor.log &

# Key log filters
docker logs -f <container> | grep -E "draft acceptance|making room|fit params|GPF|initializing"
journalctl -b -xe | grep -E "llama-server|Xe|GPF"
```

Watch host memory peaks more than VRAM (host peaked 26 GB+ + swap).

## 9. Common pitfalls

- Never set `GGML_SYCL_DISABLE_OPT` (kills SYCL kernel performance / correctness).
- Do not use the default intel/ggml images — use the B70-AOT custom image (default has no B70 kernels).
- f16 KV + MTP + ≥96k → near-certain OOM.
- Low-acceptance drafts (e.g. 2B) slow you down rather than helping.
- Logged token/s is not the real speed.

## 10. References

- [`docs/B70-TUNING.md`](./B70-TUNING.md) — hands-on flags and pitfalls.
- [`benchmark/METHODOLOGY.md`](../benchmark/METHODOLOGY.md) — test methodology.
- [`benchmark/configs/mtp4-128k.md`](../benchmark/configs/mtp4-128k.md) & [`benchmark/results/2026-08-21-mtp4-128k.md`](../benchmark/results/2026-08-21-mtp4-128k.md) — extreme 5/5 + vision.
- [`benchmark/configs/v030-u26-mtp4-q8.md`](../benchmark/configs/v030-u26-mtp4-q8.md) & [`benchmark/results/2026-08-25-v030-u26-mtp4-q8.md`](../benchmark/results/2026-08-25-v030-u26-mtp4-q8.md) — **recommended / current production (v0.3.0 + u26 base, MTP4, Q8, upgrade stack).**
- [`benchmark/configs/mtp3-q8-128k.md`](../benchmark/configs/mtp3-q8-128k.md) & [`benchmark/results/2026-08-25-mtp3-q8-128k.md`](../benchmark/results/2026-08-25-mtp3-q8-128k.md) — prior Q8 production (MTP3, superseded by MTP4).
- [`benchmark/results/2026-08-21-mtp3-96k.md`](../benchmark/results/2026-08-21-mtp3-96k.md) — legacy-safe 5/5 (pre-upgrade).
- [`benchmark/incidents/2026-08-21-gpu-dropout.md`](../benchmark/incidents/2026-08-21-gpu-dropout.md) — dropout record.
- [`examples/qwen27b-server.sh`](../examples/qwen27b-server.sh) — current recommended launch script.

**In short:** prebuilt container + **MTP4/128K + KV q8_0 + Q8 MTP draft + Q8 mmproj** on the **v0.3.0 + ubuntu26.04** upgrade stack (`:stable`). MTP4 acceptance is on par with MTP3 (≈0.57) with longer accepted runs. Any new config (higher n-max, f16 KV, larger ctx, BF16 draft at 128k) must first be validated for memory and dropout risk.