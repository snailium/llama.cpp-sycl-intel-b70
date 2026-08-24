# mtp3-96k — Recommended

- **Purpose:** The **recommended** everyday configuration — a high-quality BF16 MTP draft with 96k context and q8_0 KV. This was the **first configuration to pass all five benchmark tasks (5/5)** and it is the best stability/latency trade-off for B70.
- **Draft:** `mtp-Qwen3.8-27B-BF16.gguf` (≈5.9 GB), `--spec-type draft-mtp`, `--spec-draft-n-max 3 --spec-draft-p-min 0.1`.
- **Context:** 96k (`--ctx-size 98304`).
- **KV cache:** **q8_0** (`--cache-type-k/v q8_0`).

## Full launch flags

```bash
--m /models/Qwen3.8-27B-Q4_K_M.gguf \
--mmproj /models/mmproj-Qwen3.8-27B-BF16.gguf \
--n-gpu-layers 999 \
--ctx-size 98304 \
--cache-type-k q8_0 --cache-type-v q8_0 \
--flash-attn on \
--spec-type draft-mtp \
--spec-draft-model /models/mtp-Qwen3.8-27B-BF16.gguf \
--spec-draft-n-max 3 \
--spec-draft-p-min 0.1 \
--port 8080 --host 0.0.0.0
```

Required environment:

```bash
ONEAPI_DEVICE_SELECTOR=level_zero:0
SYCL_CACHE_PERSISTENT=0
ZES_ENABLE_SYSMAN=1
```

## Memory footprint

- Main model ≈ 18.9 GB + MTP draft ≈ 5.9 GB + mmproj.
- q8_0 KV is what makes the 5.9 GB draft affordable inside 32 GB — with f16 KV this exact stack OOMs (see METHODOLOGY §4 and the incident log).
- Observed realistic single-stream decode ≈ **33–35 t/s**; acceptance 0.57–0.85.

## When to use / avoid

- **Use for the recommended default** when 96k context is enough.
- **Avoid f16 KV** with this stack — it is the confirmed OOM trigger on agent chains.
- If you need the full 128k context, prefer [mtp4-128k](./mtp4-128k.md) (slightly higher latency, same q8_0 lifeline).

## Linked report

- `benchmark/results/2026-08-21-mtp3-96k.md`