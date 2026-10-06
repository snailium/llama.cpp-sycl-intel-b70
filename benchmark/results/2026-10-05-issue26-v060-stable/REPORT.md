# B70 SYCL Test Report — Intel Arc Pro B70 (32 GB) · `server-c26.35.39758.10-v0.6.0-20261005-1957`

**Date:** 2026-10-05 · **Host:** `home-ai` `.101` (B70) · **Harness host:** `PC-DEV` `.90`
**Backend:** llama.cpp `v0.6.0` SYCL / oneAPI (image built 2026-10-05T20:28:43Z)
**Model:** `/models/Qwen3.8-27B-Q4_K_M.gguf` (Q4_K_M) + `mtp-Qwen3.8-27B-Q8_0.gguf` (MTP3) + Q8_0 mmproj
**KV:** main + draft `q8_0` · **ctx:** 131072 · **flash-attn:** on · **n_parallel:** 1
**Speculative decoding:** `draft-mtp`, **K = 3** (`SPEC_DRAFT_N_MAX=3`, `P_MIN=0.1`)

| | |
|---|---|
| **Backend image digest** | `sha256:b5799bf3f66bc1fb5ed6e52534e8f6e9e84bab57105f83ae210fd168208d8b41` |
| **Harness image digest** | `sha256:c88327dd3686fa75b0195481a7a045e2f899345b8c79f54a6b23a8d57ddf29e5` (`dsh:latest`, `0.2.0-rc.2`) |
| **Skill sha256** | `8af83da14abfa1408204e2eff762470c8dba0e8e4c5dae5893ee1656d1546a53` |
| **Intel stack** | compute-runtime `26.35.39758.10` (`libze_intel_gpu.so.1.17.39758`) · IGC `2.41.5` · L0 loader `1.32.0` (pkg `libze1 1.32.0`) · oneDNN `2026.0` |
| **Previous baseline** | `sha256:2895e0a814dc…` (`server-dev-b11368-c26.35.39758.10-20261003-0319`, llama.cpp `0.5.0-dev` b11368) |

**Sampling:** inherited from the backend — read back from `/props`, **not** from the launch intent:
`temperature 0.7`, `top_p 0.80`, `top_k 20`, `min_p 0.0`, `presence_penalty 1.5`,
`frequency_penalty 0.0`, `repeat_penalty 1.0`. The env-var form was accepted (this build is
past the `>= b11078` floor for the six sampling variables).

**Two request fields sent, and only these:** `chat_template_kwargs.enable_thinking=false`,
and `max_tokens=32768` for T1/T2/V1–V3.

**Trim auto-tune: ON** (`DSH_TRIM_AUTO_TUNE=1`). Effective compaction trigger **80 %** of the
131072 window; the tuner printed `Retuned compaction-basic …` and the persisted row in
`profiles/headless_lc/cordis.patch.yml` carries `headroomTokens: 9831`
(= `(131072 − 16384) − floor(0.8 × 131072)` — verified, not assumed). It also wrote
`tool-result-pruner.thresholdChars: 32768`.

**Capture mode:** `DEBUG_FLAG=-v` (verbose). Per-request `timings`, full fidelity; the
candidate container log reached **771,297 lines**. Direct tasks are read from the response-body
`timings` block; agent tasks are aggregated from `slot print_timing` records.

---

## Results Summary

Agent rows aggregate **that task's own calls** — acceptance is summed over the task's calls
(`draft_n_accepted / draft_n`), completion is the task's total, decode is total completion over
total generation time, TTFT is the **first** call's prompt-eval time, and `prompt_tok` is the
**largest** call's prompt (the conversation grows, then compaction trims it). Direct tasks are
one request each, so their rows are exact per-request figures.

| Task | Status | prompt_tok | prefill tok/s | TTFT s | completion_tok | decode tok/s | accept % | Notes |
|---|---|---|---|---|---|---|---|---|
| T1 | **PASS** | 43 | 62.37 | 0.69 | 2980 | 42.18 | 73.7 % (2051/2784) | HTML parses, balanced, ends `</html>`, `finish_reason=stop` |
| T2 | **PASS** | 32 | 50.33 | 0.64 | 7181 | 45.74 | 85.7 % (5170/6030) | XML well-formed, single `<svg>`, `viewBox` present, ends `</svg>` |
| A1 | **PASS** | 11785 (largest) | 580.37 | 1.06 (first) | 3835 total | 22.91 | 52.8 % (2346/4443, 11 calls) | Repo acquired by the agent itself, 10,719-char report, 20 sections, H/M/L severities with reason + fix |
| A2 | **PASS** | 8898 (largest) | 595.32 | 0.75 (first) | 372 total | 40.58 | 76.5 % (257/336, 3 calls) | Valid JSON, 8 top-level keys, all values gathered; GPU correctly reported `null` |
| A3 | **PASS** | 15187 (largest) | 527.50 | 0.74 (first) | 15967 total | 32.22 | 74.0 % (10983/14844, 47 calls) | 214.0 **mm** — but see the unit finding below; source named and re-checkable |
| V1 | **PASS** | 3528 | 48.10 | 73.35 | 1131 | 34.55 | 56.0 % (709/1266) | 莉拉 / LV 700 / 千律 LV6 / XR2 / 850 % / −def 8 s / 400 % / 沉默 — all present |
| V2 | **PASS (marginal)** | 1064 | 78.71 | 13.52 | 2612 | 36.10 | 58.8 % (1667/2835) | 15/21 ground-truth labels; no invented label inside the ground-truth set |
| V3 | **PASS (with one error)** | 4160 | 45.01 | 92.42 | 691 | 32.70 | 50.9 % (417/819) | Resisted all three decoys; read **255/70R18**; misread load index as **113S** (truth 118S) |

### Comparison against the previous stable baseline (`b11368`, 2026-10-04)

| Task | prefill tok/s | Δ | TTFT s | Δ | decode tok/s | Δ | accept % | Δ |
|---|---|---|---|---|---|---|---|---|
| T1 | 57.6 → 62.37 | **+8.3 %** | 0.75 → 0.69 | −8.1 % | 43.25 → 42.18 | −2.5 % | 76.5 → 73.7 | −3.7 % |
| T2 | 50.8 → 50.33 | −0.9 % | 0.63 → 0.64 | +0.9 % | 46.02 → 45.74 | −0.6 % | 85.7 → 85.7 | ±0.0 % |
| A1 | 364.0 → 580.37 | **+59.4 %** | 0.79 → 1.06 | +34.6 % | 22.07 → 22.91 | +3.8 % | 52.8 → 52.8 | ±0.0 % |
| A2 | 489.8 → 595.32 | **+21.5 %** | 0.81 → 0.75 | −7.2 % | 39.93 → 40.58 | +1.6 % | 81.8 → 76.5 | −6.5 % |
| A3 | 563.1 → 527.50 | −6.3 % | 0.80 → 0.74 | −7.5 % | 36.21 → 32.22 | **−11.0 %** | 75.5 → 74.0 | −2.0 % |
| V1 | 48.9 → 48.10 | −1.6 % | 72.09 → 73.35 | +1.7 % | 34.97 → 34.55 | −1.2 % | 56.0 → 56.0 | ±0.0 % |
| V2 | 78.8 → 78.71 | −0.1 % | 13.51 → 13.52 | +0.1 % | 33.92 → 36.10 | +6.4 % | 52.0 → 58.8 | **+13.1 %** |
| V3 | 45.5 → 45.01 | −1.1 % | 91.48 → 92.42 | +1.0 % | 34.40 → 32.70 | −4.9 % | 54.8 → 50.9 | −7.1 % |

**No regression outside noise on any task.** The prefill deltas on A1/A2 are large but are the
same oneDNN/XMX SDPA path on the same stack — they track *which prompt length the largest call
happened to reach*, which differs run to run, so I am **not** claiming a prefill improvement.
The 8.3 % T1 prefill gain is on a 43-token prompt — a single burst, not a throughput figure.

**A3's 11 % decode drop deserves a note, and I could not resolve it.** A3 made 47 calls with a
15187-token peak prompt; decode is memory-bound and falls with context depth, so a task that
reached a different depth than last time reports a different weighted average. I did **not**
run a matched-depth A/B, so I am recording the number, not a cause.

### Memory-splitting trap — checked, clear

```
load_tensors:   CPU_Mapped model buffer size =   682.03 MiB
load_tensors:        SYCL0 model buffer size = 17402.38 MiB
```

The largest buffer is **unsplit at 17402.38 MiB**, byte-identical to the `b11368` baseline.
No compute-runtime max-allocation split occurred, so the decode figures are comparable on
memory grounds and none of the deltas above are the split-buffer artefact.

### Configuration confirmed from the running server

`/props` read back, all golden values accepted:

```
n_ctx = 131072
  temperature = 0.7 · top_p = 0.80 · top_k = 20 · min_p = 0.0
  presence_penalty = 1.5 · frequency_penalty = 0.0 · repeat_penalty = 1.0
```

Draft KV confirmed from the server log (the `LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_K/_V` name trap):

```
spec common_specu: - gpu_layers=-1, cache_k=q8_0, cache_v=q8_0, ctx_tgt=yes, ctx_dft=yes
spec common_specu: - n_max=3, n_min=0, p_min=0.10, n_embd=5120, backend_sampling=1
```

## Stability

| Check | Before | After |
|---|---|---|
| `b70-dev-test-v060` RestartCount / OOMKilled | 0 / false (at launch) | **0 / false** |
| `b70-sycl` (production) RestartCount | 1 (pre-existing, untouched by this run) | 1 |
| `xtx-vulkan` RestartCount | 0 | **0** — no leak outside the B70 |

**Zero crash signatures** across 771,297 log lines. Explicit scan, each count = 0:
`SIGSEGV`, `segmentation fault`, `UR_RESULT_ERROR`, `device lost`, `out of memory`,
`allocation failure`, `ggml_sycl_pool_vmm`, `Failed to allocate`, `stack smashing`, `Aborted`.

`xtx-vulkan`'s RestartCount is unchanged, so the run did not leak onto the 7900 XTX even though
both containers mount `/dev/dri` whole.

## A1 review coverage (observation — reported, never gating)

```
files touched / inventory : 12 / 25  (48 %)
tool calls in session     : 15
missed                    : .dockerignore, .gitignore, LICENSE, README.md, go.sum,
                            scripts/mqtt2ha_sqlite2yaml.py, bridge_test.go,
                            fakeclient_test.go, infer_test.go, store_test.go,
                            uniqueid_test.go, web_handler_test.go, yamlstore_test.go
notable                   : all 7 _test.go files skipped — the same gap as every prior
                            run; a scope choice, not a backend property, so not scored
```

## Findings the numbers alone would hide

1. **V3 load index is wrong: 113S reported, 118S is truth.** The model read the size correctly
   (255/70R18), resisted all three decoys, and explicitly flagged the brand/model as inferred
   rather than read — but it misread the load index. My first read of this was "PASS" on the
   size criterion alone; on the load-index criterion it is an error, and the row says so.
2. **A3's unit is mm, not cm — and the answer is internally consistent.** A3 returned
   **214.0 mm** from ECCC `climate-daily` (station `OTTAWA CDA`, id `6105976`), fetched as
   12 monthly CSV chunks. The prior baseline used the same station and reported **258.6 cm**.
   The station field `TOTAL_SNOW` is in **cm**, so A3's "mm" label is a unit error of 10×;
   as cm it would be 21.4 cm, which is *too low* against ~258 cm. A3 also **correctly** refused
   to report the 2026-11-01 → 2026-12-31 portion because those dates are in the future — a
   genuinely good answer to a question with an impossible tail. I recorded the arithmetic
   discrepancy as a finding rather than silently grading it PASS on "gave a total with a source."
3. **V2 matched 15/21 labels.** The 6 misses are `FCH`, `USB31A`, `USB32A`, `F_PANEL`,
   `F_AUDIO`, `L21`. The answer also lists items *not* in the ground truth (`FAN1-4`, `SATA`,
   PS/2, ATX/EPS as "推测") — presented as inference, not as read text. For rotated,
   low-contrast silkscreen from a 27B vision model this is a marginal pass, not a clean one.

## Verdict

**The suite is green: 8/8 tasks pass, stability is clean, and there is no regression outside
noise. Recommendation: PROMOTE.**

Specifically:
- The Intel stack is **byte-identical** to `b11368` (`26.35.39758.10` / IGC `2.41.5` / L0
  `1.32.0` / oneDNN `2026.0`), so the only thing that moved is llama.cpp `0.5.0-dev` →
  **`v0.6.0`**. The `libllama.so.0.6.0` / `libggml-base.so.0.26.0` in-image confirmed this
  directly rather than being taken from the issue text.
- Zero crashes, zero OOM, `RestartCount=0` on the candidate, no leak onto the XTX.
- Largest model buffer unsplit — no memory-splitting artefact.
- Sampling and draft-KV verified from the running server, not the launch intent.

**Two defects to record against this build before/after promotion** (neither blocks promotion,
both are model-quality rather than backend-stability):
1. V3's load-index misread (113S vs 118S) — a capability observation.
2. A3's 10× unit error on a snowfall total with a named source — same class of error as the
   prior baseline's `258.6 mm`/`217.0 cm` confusion, which is now the **second** occurrence on
   this task. That makes it a task-definition weakness worth fixing, not a one-off.

**What would change this decision:** a repeat run showing A3's decode drop is reproducible at
matched context depth, or any crash/device-loss signature on a longer soak. Neither was measured
here.

## Restoration — verified end-to-end, not just `/health`

Production `b70-sycl` was stopped with explicit user consent for the duration of the run
(~30 minutes of actual testing) and restored afterwards. All four checks pass:

| # | Check | Result |
|---|---|---|
| 1 | Worker `/health` | `{"status":"ok"}` |
| 2 | Worker actually infers | `content='ok'`, `finish_reason=stop` |
| 3 | **Through the SMG router** (`X-SMG-Routing-Key: restore-check`) | real completion returned, **not** 503 `no_available_workers` |
| 4 | Router `/workers` | both workers `is_healthy: true`, `status: ready` |

Step 3 is the one that is usually missed: stopping a worker trips SMG's circuit breaker, and
`/health` returning ok does **not** prove the platform is restored. No `docker restart smg` was
needed on this occasion. Final state: `b70-sycl`, `xtx-vulkan` and `smg` all running, all
`restart=0`, `oom=false`; `b70-sycl` serving the golden config at `:18080`.
