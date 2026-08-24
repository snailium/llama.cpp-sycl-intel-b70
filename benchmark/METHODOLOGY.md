# Benchmark Methodology

This document defines the test methodology used by every report under `benchmark/results/`. Describing methods up front keeps reports comparable and reproducible.

> Reference: benchmarks measure **llama.cpp + SYCL** running **Qwen3.8-27B (Q4_K_M)** on a single **Intel Arc Pro B70** (32 GB, BMG-G31). For backend-to-backend comparisons (vLLM, Ollama, OpenVINO), only the contended metrics in this document are used.

## 1. Workload and environment

- **Model stack (ggml-org, all BF16 where applicable):**
  - Main model: `Qwen3.8-27B-Q4_K_M.gguf` (≈18.9 GB)
  - Multimodal projector: `mmproj-Qwen3.8-27B-BF16.gguf`
  - MTP draft (when speculative mode is used): `mtp-Qwen3.8-27B-BF16.gguf` (≈5.9 GB)
- **GPU:** Intel Arc Pro B70, 32 GB VRAM, PCIe Gen3.
- **Host kernel flag:** `pcie_aspm=off` (required to prevent B70 PCIe link drops — see `benchmark/incidents/`).
- **Server:** `llama.cpp-sycl-b70:server` container, OpenAI-compatible endpoint at `:18080/v1`.

## 2. The five-task test suite (T1–T5)

Every benchmark report runs the same five tasks so results can be compared across configs and backends.

| ID | Task | Type | Notes |
|----|------|------|-------|
| T1 | Historical **HTML** page | Direct API, single-shot | Dense generation artifact; must close all tags |
| T2 | Big-Bang **SVG** artwork | Direct API, single-shot | Large structured artifact; must be complete |
| T3 | Security review of an MQTT→Home Assistant bridge | Agent (tool use) | Long, multi-tool reasoning chain |
| T4 | Host system config **JSON** report | Agent (tool use) | Requires real host data via tools |
| T5 | Ottawa YOW snowfall research | Agent (tool use) | Long research task; cross-validated sources |

- **T1/T2** are single-generation artifact tasks hit over the OpenAI-compatible endpoint (no tools).
- **T3/T4/T5** are agentic workloads run through an external agent harness that substitutes real tool calls (shell, web search) for the model's tool invocations, exercising long, continuously growing context.

**Thinking mode must be OFF for all artifact tasks.** Qwen3.8 runs thinking by default and it consumes the token budget; turning it on causes reasoning-heavy runs that never emit code (a 27B class model can hit the token ceiling with zero artifact output). Disable thinking via
`chat_template_kwargs.enable_thinking=false` (direct API) / `think:false` (Ollama).

## 3. Metrics and how they are measured

| Metric | Definition / Source | Caveat |
|--------|---------------------|--------|
| **Decode t/s** | Token generation rate; read from the **streamed `tg`** field or single-shot `timings` | Do **not** use llama.cpp's logged `eval time ... / N tokens` as the user-facing rate — it is a batched speculative throughput figure and can read 33–143 t/s (inflated). |
| **Prompt (prefill) t/s** | Prompt processing throughput | Varies strongly with context length and KV-cache hits. |
| **TTFT** | Time to first token | Only meaningful for cold short prompts; near zero for long agent turns. |
| **Draft acceptance** | `accepted / generated`, aggregated from llama.cpp `draft acceptance` log lines | Only present for speculative (MTP/2B-draft) configs; absent for no-draft runs. |
| **Wall time / EXIT** | Total task duration and agent-harness exit status | `EXIT=0` means the task completed; for agent tasks this is the primary correctness gate. |
| **VRAM / host RAM** | Observed container memory peaks | Host RAM is the more dangerous limit — a VRAM overflow spills to host RAM and can trigger the OOM killer (see below). |

### Reporting conventions
- Record **both** the wall time and the best available decode t/s.
- For agent tasks, always record `EXIT` status and draft acceptance **per task**.
- State which KV cache type was used (f16 vs q8_0) — it is the single biggest stability lever.

## 4. Known pitfalls that affect measurements

- **Batch `eval time` is not the real speed.** llama.cpp logs per-block `eval time ... / N tokens` that includes speculative batching and cache hits. Always report from streamed `tg` or single-shot `timings`.
- **`--cache-type-k/v q8_0` is the KV lifeline.** With f16 KV, an MTP performance/draft (≈5.9 GB) plus a large context crowds out KV capacity, VRAM overflows to host RAM and long agent chains OOM. q8_0 roughly halves KV and restores the safety margin. f16 is fine for short contexts only.
- **Low-quality drafts are a net drag.** A small 2B draft with acceptance 0.31–0.50 makes generation *slower*, not faster. Only high-quality drafts (BF16 MTP, acceptance 0.57–0.91) justify the VRAM they cost.
- **Verifying the card is actually alive** requires a real `/v1/chat/completions` response with `finish_reason=stop`. Container "up" or `lspci` presence is not sufficient; check `dmesg` for `wedged / reset failed / GuC no reply` to detect an un-recovered card.

## 5. Report template

Every report under `benchmark/results/` follows this shape:

```markdown
# <Date> — <config short name>

- Config: [<config>](../configs/<config>.md)
- Result: full pass / partial / fail, and which tasks

## Summary
One-paragraph verdict: what passed, headline numbers, what changed vs prior runs.

## Environment
GPU, host kernel flag, container, exact command (or link to config file).

## Results
| Task | Wall time | EXIT | Decode t/s | Prompt t/s | TTFT | Draft acceptance |

## Metrics & caveats
Decode source, KV type, memory peaks, anything that skews numbers.

## Conclusion
Verdict, what was learned, recommendation.
```

## 6. Adding a new benchmark

1. Copy `configs/<your-config>.md` from the template in `configs/README.md`.
2. Run the full five-task suite (T1–T5) with thinking off, using the metrics table above.
3. Record the results using the report template into `results/<YYYY-MM-DD>-<config>.md`.
4. Link the new report from `benchmark/README.md`.
5. If you find a stability or dropout incident, add it to `incidents/` instead.