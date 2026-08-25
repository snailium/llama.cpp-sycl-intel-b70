# Benchmarks — llama.cpp SYCL on Intel Arc Pro B70

Performance and stability benchmarks for llama.cpp SYCL running a 27B-class model (Qwen3.8-27B) on a single Intel Arc Pro B70 (32 GB, BMG-G31).

## Layout

```
benchmark/
├── README.md        ← you are here (index)
├── METHODOLOGY.md   ← test methodology (tasks, metrics, conventions)
├── configs/         ← one file per reproducible server config
├── results/         ← one file per dated test run
└── incidents/       ← stability / dropout incident logs
```

**Start with [METHODOLOGY.md](./METHODOLOGY.md)** — it defines the five-task suite (T1–T5), the metric definitions, and the reporting rules that make all reports comparable. **Configs** are declared once and referenced by every run; **results** are the dated numbers produced against those configs.

## Recommended configuration

The current recommended default is **F16 KV + 96k + Q4_0 MTP draft, MTP3/0.1 + Q8 mmproj**, on the **v0.3.0 + oneDNN/XMX** image ([config](./configs/v030-f16-96k-dnn-mtp3-q4.md)) — XMX prefill ≈392 t/s, decode ≈26.2 t/s, draft acc 0.573, +1.5GB VRAM headroom. The `examples/qwen27b-server.sh` launcher matches this config.

> The **Q8 (not BF16) MTP draft is required on the upgrade stack at 128k** — the BF16 draft's speculative buffer reserve crashes the 32 GB card (`Failed to allocate physical memory`). Quantizing to Q8 frees ~1.5 GB and enables 128k with no acceptance loss.

Two rules drive every recommendation:
1. **q8_0 KV** is the lifeline — without it, MTP + large context OOMs (f16 KV is short-context-only).
2. **Thinking must be OFF** for artifact tasks, and **low-acceptance drafts are a net drag** (see methodology).

## Configurations

| Config | Draft | Context | KV | Role |
|--------|-------|---------|----|------|
| [v030-u26-mtp4-q8](./configs/v030-u26-mtp4-q8.md) | Q8_0 MTP n=4 | 128k | q8_0 | Prior production (full 128k; superseded by DNN/XMX) |
| [mtp3-q8-128k](./configs/mtp3-q8-128k.md) | Q8_0 MTP n=3 | 128k | q8_0 | Prior production (superseded by MTP4) |
| [draft2b-128k](./configs/draft2b-128k.md) | 2B (disproven) | 128k | q8_0 | Speculative-vs-not baseline |
| [nodraft-vision-128k](./configs/nodraft-vision-128k.md) | none | 128k | f16 | Stable text + vision workhorse |
| [mtp3-96k](./configs/mtp3-96k.md) | BF16 MTP n=3 | 96k | q8_0 | Legacy-safe 96k (pre-upgrade) |
| [mtp4-128k](./configs/mtp4-128k.md) | BF16 MTP n=4 | 128k | q8_0 | Max context / max MTP (old stack) |

## Results

| Date | Report | Config | Outcome |
|------|--------|--------|---------|
| 2026-08-20 | [draft2b-128k](./results/2026-08-20-draft2b-128k.md) | draft2b-128k | 3/3 agent tasks; proves q8_0 fix + 2B-draft drag |
| 2026-08-20 | [nodraft-vision-128k](./results/2026-08-20-nodraft-vision-128k.md) | nodraft-vision-128k | 3/3 agent tasks; dropping 2B draft speeds up T3/T4 |
| 2026-08-21 | [mtp3-96k](./results/2026-08-21-mtp3-96k.md) | mtp3-96k | **5/5**; legacy-safe pre-upgrade |
| 2026-08-21 | [mtp4-128k](./results/2026-08-21-mtp4-128k.md) | mtp4-128k | **5/5 + 3 vision**; extreme vertex config (old stack) |
| 2026-08-25 | [mtp3-q8-128k](./results/2026-08-25-mtp3-q8-128k.md) | mtp3-q8-128k | **Full suite pass** + T5 310 cm on upgrade stack; gate for `:stable` |
| 2026-08-25 | [v030-u26-mtp4-q8](./results/2026-08-25-v030-u26-mtp4-q8.md) | v030-u26-mtp4-q8 | **Full suite (T1–T5 + V1–V3) pass**, 0 crashes, MTP4 acc 0.57; promoted to `:stable`/`:v0.3.0` |
| 2026-08-25 | [v030-f16-96k-dnn-mtp4](./results/2026-08-25-v030-f16-96k-dnn-mtp4.md) | v030-f16-96k-dnn-mtp4 | DNN/XMX prefill **430 t/s vs 212**, decode 22.2; VRAM edge (R1) |
| 2026-08-25 | [v030-f16-96k-dnn-mtp3-q4](./results/2026-08-25-v030-f16-96k-dnn-mtp3-q4.md) | v030-f16-96k-dnn-mtp3-q4 | DNN/XMX **stable**: prefill 392, decode 26.2, acc 0.573, +1.5GB VRAM (R2) |

## Incidents

| Date | Report | Summary |
|------|--------|---------|
| 2026-08-21 | [gpu-dropout](./incidents/2026-08-21-gpu-dropout.md) | B70 PCIe link dropout after heavy MTP load (B450); recovery + mitigation |

## Headline numbers (for quick reference)

- **Recommended decode:** ≈ 24–28 t/s single-stream (MTP3/Q8/128K), ≈8% over the ≈23.2 t/s no-draft baseline; **TTFT ≈ 0.88 s** (MTP4/128K, old stack).
- **Long-chain draft acceptance:** 0.50–0.85 (BF16 MTP) vs 0.31–0.50 (2B draft).
- **Full agent suite:** llama.cpp is the **only B70 backend that completes all tasks** — vLLM-MTP crashes on T5.
- **Vision:** quality on par with a dual-3060 27B, but much slower (visual prefill bottleneck).

## Adding a new benchmark

1. Copy a config under `configs/` (template in `configs/README.md`).
2. Run the full five-task suite (T1–T5, thinking off) per [METHODOLOGY.md](./METHODOLOGY.md).
3. Record results using the report template into `results/<YYYY-MM-DD>-<config>.md`.
4. Stability/incidents go into `incidents/`.
5. Link the new files from this README.