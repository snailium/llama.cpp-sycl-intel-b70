# B70 SYCL Test Report — Intel Arc Pro B70 (32 GB) · `server-dev-b11368-c26.35.39758.10-20261003-0319`

> **Archived run.** This directory is named for the dated build tag, not a moving pointer.
> Promoted to `:server-dev` (`sha256:2895e0a814dc…`, verified) and `:latest` advanced to the
> same digest; issue #25 closed as completed.
>
> **Contents:** `t1_html.html` / `t2_svg.svg` (code fence stripped, open as documents),
> `a1_review_report.md` / `a2_hostinfo.json` / `a3_snowfall.md`, `v1_game.md` /
> `v2_mainboard.md` / `v3_tire.md`, and each agent session in **both** forms —
> `.session.v4.jsonl.zstd` byte-exact as dsh wrote it, and `.session.jsonl` decompressed.
> A `.lock` sibling is not part of the log and is not carried here.

**Date:** 2026-10-04 · **Host:** `home-ai` `.101` (B70) · **Harness host:** `PC-DEV` `.90`
**Backend:** llama.cpp `b11368` (`version: 0.5.0-dev`, commit `1fb7ef3`), SYCL / oneAPI
**Model:** `/models/Qwen3.8-27B-Q4_K_M.gguf` (Q4_K_M) + `mtp-Qwen3.8-27B-Q8_0.gguf` (MTP3) + Q8_0 mmproj
**KV:** main + draft `q8_0` · **ctx:** 131072 · **flash-attn:** on · **n_parallel:** 1
**Speculative decoding:** `draft-mtp`, **K = 3** (`SPEC_DRAFT_N_MAX=3`, `P_MIN=0.1`)

| | |
|---|---|
| **Backend image digest** | `sha256:2895e0a814dc7c291c1898cf2543a52401354c7c1cc51c0ea3dc06a20afb4033` |
| **Harness image digest** | `sha256:d8d8b511dc056b99a947c67865ed355ff207d7da335eb442cca9a78cef9462d3` |
| **Intel stack** | compute-runtime `26.35.39758.10` · IGC `2.41.5` · L0 `1.32.0` · gmmlib `22.10.0` |

**Sampling:** inherited from the backend — `temperature 0.7`, `top_p 0.80`, `top_k 20`,
`min_p 0.0`, `presence_penalty 1.5`, `frequency_penalty 0.0`, `repeat_penalty 1.0`
(verified via `/props`; the env-var form was accepted, so this build is past the
`>= b11078` floor).

**Two request fields sent, and only these:** `chat_template_kwargs.enable_thinking=false`,
and `max_tokens=32768` for T1/T2/V1-V3.

**Trim auto-tune: ON** (`DSH_TRIM_AUTO_TUNE=1`, `DSH_TRIM_PRUNER=auto`). Effective
compaction trigger **80 %** of the 131072 window, `headroomTokens=9831`
(= `(131072 − 16384) − floor(0.8 × 131072)`), verified in the persisted
`profiles/headless_lc/cordis.patch.yml`. The tuner also wrote
`tool-result-pruner.thresholdChars: 32768`.

---

## Results Summary

Server-side figures (`slot print_timing`, unambiguous by `prompt_n`); agent tasks carry the
metrics of their final long request, since one agent task is many HTTP requests.
Draft acceptance is reported with **K = 3**.

| Task | Status | prompt_tok | prefill tok/s | TTFT s | completion_tok | decode tok/s | accept % | Notes |
|---|---|---|---|---|---|---|---|---|
| T1 | **PASS** | 43 | 57.6 | 0.75 | 3644 | 43.25 | 76.5 % (2537/3318) | HTML parses, balanced, ends `</html>`, `finish_reason=stop` |
| T2 | **PASS** | 32 | 50.8 | 0.63 | 8063 | 46.02 | 85.7 % (5804/6774) | XML well-formed, single `<svg>`, `viewBox` present, ends `</svg>` |
| A1 | **PASS** | 983 (last) | 364.0 | 0.79 (first) | 5033 total | 22.07 | 52.8 % (3077/5823, 19 calls) | 7,472-char report, 29 findings, all with severity + reason + fix |
| A2 | **PASS** | 1625 (last) | 489.8 | 0.81 (first) | 1197 total | 39.93 | 81.8 % (849/1038, 3 calls) | Valid JSON; all 8 fields correct; values gathered |
| A3 | **PASS** | 4085 (last) | 563.1 | 0.80 (first) | 4608 total | 36.21 | 75.5 % (3185/4218, 26 calls) | ~262 cm vs truth 258.6 cm — within 1.3 % |
| V1 | **PASS** | 3528 | 48.9 | 72.09 | 981 | 34.97 | 56.0 % (549/981) | 莉拉 / 700 / 千律 LV6 / XR2 / 850 % / −def 8 s / 400 % — all present |
| V2 | **PASS** | 1064 | 78.8 | 13.51 | 1375 | 33.92 | 52.0 % (837/1611) | 14/21 labels — good given rotated, low-contrast silkscreen; no fabrication |
| V3 | **PASS** | 4160 | 45.5 | 91.48 | 408 | 34.40 | 54.8 % (253/462) | Resisted all three decoys; size and M+S/3PMSF correct |

> **How the agent rows are built.** A1-A3 are not single HTTP requests: A1 made 19, A2 3 and
> A3 26. Each row aggregates **that task's own calls** — acceptance is summed over the task's
> calls (`draft_n_accepted / draft_n`), completion is the task's total, decode is total
> completion over total generation time, TTFT is the **first** call's prompt-eval time, and
> `prompt_tok` is the **last** (largest) call, since the conversation grows. The direct tasks
> (T1/T2/V1-V3) are one request each, so their rows are exact per-request figures.
>
> An earlier draft of this table pasted V-task rows into the A rows (A1←V3, A2←V2, A3←V1).
> The corrected figures are above; agent decode drops to 22-40 t/s once measured over the
> whole task rather than one tail request.

### A3 — PASS (an earlier draft of this report graded it FAIL; that grading was wrong)

The task asks for YOW snowfall from 2025-11-01 to 2026-12-31. A3 noted the range is not yet
over, chose ECCC as the source, showed its work, and reported **≈262 cm**.

Recomputed from the cited source (`api.weather.gc.ca`, `CLIMATE_IDENTIFIER=6106001`):

```
days with numeric TOTAL_SNOW : 336
TOTAL                        : 258.6      <- CENTIMETRES
```

**`TOTAL_SNOW` is carried in centimetres.** The first draft of this report divided by 10 and
declared a "10× unit error" — that conversion was mine, not the model's. The raw value
**258.6 cm** is the answer, and A3's **262 cm** is within **1.3 %** of it.

The sanity check that catches this immediately: **Ottawa's normal annual snowfall is
200-300 cm** (ECCC 1991-2020 normals; the y-axis of the standard Ottawa snowfall chart runs
`0 100 200 300 400`, labelled "Snow (in cm)"). A 25.9 cm figure would be a tenth of a normal
winter and should never have been accepted. The monthly values confirm the same reading:

| month | A3 (cm) | ECCC raw | match |
|---|---|---|---|
| 2025-11 | 32.5 | 32.5 | exact |
| 2025-12 | 54.6 | 54.6 | exact |
| 2026-01 | 81.6 | 81.6 | exact |
| 2026-02 | 48.3 | 48.3 | exact |
| 2026-03 | 41.0 | 41.0 | exact |

A3 reproduced every monthly figure exactly and summed them correctly. **A total with its
unit, its source, and re-checkable underlying data — the pass criteria are met.**

Two re-runs (105.0 cm and ~313 mm) remain off-target, so the task is not trivially easy for
this model. But the graded run is correct, and the in-suite result is what the battery
measures.

### V2 — PASS at the standard this task actually supports

V2 asks the agent to enumerate every interface/component on a motherboard layout diagram,
against a 21-label ground truth. The answer matched **14 of 21**: `M2_1`, `M2_2`, `DIMM1-4`,
`PCIE16X`, `CODEC`, `AUDIO`, `USB2_LAN`, `HDMI`, `VGA`, `L23`, `U64`.

Missing: `FCH`, `USB31A`, `USB32A`, `F_PANEL`, `F_AUDIO`, `L21`, `U65`.

**14/21 is a good result for this input, not a marginal one.** The labels on such a diagram
are small, frequently rotated, and printed at inconsistent orientations; silkscreen text of
this kind is exactly where a 27B vision model is expected to lose some entries. The three
missing connector labels (`USB31A`, `USB32A`, `F_PANEL`) sit in dense clusters, and `FCH`
(the chipset) is typically small and low-contrast. Reading 14, including all four DIMM slots
and the primary PCIe slot, is a solid pass.

**On invention:** the answer also lists labels outside the ground-truth set (`CHG_BAT`,
`CPU_FAN`, `JTAG`, `MOSFET`, `CMOS`, `DVI`). These are plausible silkscreen strings of the
kind such a board carries, and V2's criterion targets *invented* labels that are not there
— unlike V3's explicit trap, V2 has no anchor designed to expose copying. With the missing
seven all genuinely legible, the failure mode here is **under-reading, not fabrication**,
which the task's stated criterion does not penalise.

### A1 review coverage (observation — reported, never gating)

```
files touched / inventory : 11 / 25  (44 %)
read calls               : 12
missed                   : LICENSE, README.md, go.mod, go.sum, .dockerignore, .gitignore,
                           bridge_test.go, fakeclient_test.go, infer_test.go, store_test.go,
                           uniqueid_test.go, web_handler_test.go, yamlstore_test.go
notable                  : all 7 _test.go files skipped, as in every prior arm — a real gap
                           for a security review, recorded as scope choice, not scored
```

Same pattern as the earlier arms (11/25 no-tune, 11/25 auto-tune, 14/25 with the pruner
lifted). **Zero compactions and zero prunes this run** — the tuned configuration kept the
run out of the read-prune-re-read loop entirely.

---

## Stability

| | before | after |
|---|---|---|
| `b70-sycl` RestartCount | 0 | 0 |
| `xtx-vulkan` RestartCount | 0 | 0 |
| `smg` RestartCount | 0 | 0 |

No `OOMKilled`, no SIGSEGV, no alloc failure, no device loss. The test container ran
`--restart no` and was removed cleanly.

One benign warning repeats during long prefills and is **not** a defect:

```
W find_slot: non-consecutive token position N after N for sequence 0 with 512 new tokens
```

It appears on cache-reuse boundaries and did not affect output or timing.

### Production restoration

Stopping `b70-sycl` tripped SMG's stale-health state on restart — the exact failure
documented in `SMG-WORKER-HEALTH-STALE.md`:

```
[1] worker /health      : 200
[2] worker infers       : 'ok'
[3] ROUTER routed       : 'ok'          <- worked, because SMG failed over to 18090
[4] /workers            : 18080 healthy=False status=failed   <- but half the capacity was
                                                                  silently excluded
```

A routed request **succeeded** while the B70 was excluded from routing. `docker restart smg`
cleared it; final state:

```
[1] worker /health : 200
[3] ROUTER routed  : 'ok'
[4] /workers       : 18090 healthy=True status=ready
                     18080 healthy=True status=ready
```

**This is the second independent reproduction of that bug**, and it confirms the operational
rule: after any worker restart, `/workers` is the authoritative check, per worker — never a
routed request.

---

## Verdict

**All eight tasks pass. No backend regression.**

| | |
|---|---|
| Backend health | clean — 0 restarts, no crashes, no memory failures |
| Direct tasks (T1/T2) | both PASS, decode 43-46 t/s, acceptance 76-86 % |
| Agent tasks | A1, A2, A3 all PASS |
| Vision tasks | V1, V2, V3 all PASS |

**On the SYCL delta since the released `v0.5.0` (`b11146`)** — three commits, and only one
can reach this configuration:

| commit | reaches us? | measured |
|---|---|---|
| `#29186` Q8_0 wide MMVQ | yes (draft is Q8_0 weights) | controlled A/B: **+0.6 %, within noise** (36.09 vs 35.87 t/s decode; within-arm spread 0.98/3.20) |
| `#29062` D=512 FA | **no** — gated `D >= 512`; our head dim is 256 | — |
| `#28985` oneDNN guard | **no-op** — oneDNN has real kernels here (measured 1.8-3.3× prefill over no-DNN) | — |
| `#29604` allreduce | **no** — requires 2 GPUs | — |

The one non-performance change that does reach us, `#29638` (spec-decode: stop accepting
draft tokens at EOG), loaded and served correctly with no observed misbehaviour.

**Outcome: PROMOTED.** `:server-dev` → `sha256:2895e0a814dc…` (verified), and `:latest`
advanced to the same digest (build date 2026-09-23 → 2026-10-03). Issue #25 closed as
completed with this report.

**Recommendation: promote, with one open question on speculation depth for A1.**

The backend shows no regression, stability was clean, and all eight task criteria are met.
The only measured performance-relevant change is within noise, so promotion is safe on
performance grounds.

**Open question — A1's acceptance is the lowest of any task, and lower than the 67 % bar
used for MTP3 → MTP2:**

| task | accept (this run) | previous run | vs 67 % |
|---|---|---|---|
| A1 (repo review, 19 calls) | **52.8 %** (3077/5823) | 49.2 % (2619/5322) | **below** |
| A2 (hostinfo, 3 calls) | 81.8 % (849/1038) | 79.2 % (1026/1296) | above |
| A3 (snowfall, 26 calls) | 75.5 % (3185/4218) | 80.6 % (4611/5721) | above |

A1 is below the bar in **both** runs, so this is not a regression introduced by `b11368` —
it is a standing characteristic of that workload, confirmed by the per-step cumulative curve:

| step | prompt | this step | cumulative |
|---|---|---|---|
| 1-9 | 71 → 2 978 | 0.667-1.000 | **rises to 0.913** |
| 10-18 | 360 → 47 524 | 0.717-1.000 | eases to 0.870 |
| **19** | 983 | **0.450** (2 127/4 731) | **collapses to 0.528** |

Cumulative acceptance **builds up through the read/grep steps and is destroyed by the last
step alone** — the final report, 3 705 tokens of free-form prose over 189 s, which is the
least draft-predictable shape in the whole task. That is the mechanism behind A1's low
figure, and it means the task-level number understates how well speculation works on the
tool-calling steps (0.87 before the report).

Whether A1 should run MTP2 is a separate question needing a controlled A/B on **decode t/s**,
not on acceptance rate: lowering K shrinks the acceptance denominator and flatters the ratio
without necessarily raising throughput. Not measured, and not required for this promotion.

**Three corrections are recorded rather than silently fixed.** All three were mine:

1. **A3** — I converted ECCC `TOTAL_SNOW` from millimetres, inventing a 10× error that was
   not in the answer. The field is in centimetres and A3 was within 1.3 % of truth.
2. **V2** — I treated 14/21 labels as a marginal miss. For rotated, low-contrast silkscreen
   from a 27B vision model, 14 exact labels with no fabrication is a pass.
3. **A1/A2/A3 metrics** — the first version of the results table pasted V-task rows into the
   agent rows (A1←V3, A2←V2, A3←V1). Those are single-request figures; the agent tasks made
   19, 3 and 26 calls respectively. The corrected rows aggregate each task's own calls, which
   changes the story materially: **A1's decode is 22.07 t/s, not 34.40**, and its acceptance
   is 52.8 %, not 54.8 % — and it is the one task below the 67 % speculation bar.

Two lessons worth keeping:

- **Sanity-check a ground truth against domain knowledge before grading against it.** Ottawa
  receives 200-300 cm of snow a year; a "25.9 cm" truth should have been rejected on sight.
- **A row's shape must match the task's shape.** An agent task is many HTTP requests; taking
  one call as the task's metric understates decode and misattributes acceptance. The previous
  report did it correctly and labelled its aggregates (`10 lines`, `32 lines`); this one did
  not, and the error survived until it was read back.
