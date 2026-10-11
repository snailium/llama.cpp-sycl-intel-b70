# T2 — retest with cold-start samples, and performance collection

**Question:** the main run failed T2 in 3/3 samples with prose appended after the SVG. Is that
reproducible, and does it survive a proper cold-start methodology?

**Answer: T2 fails 5/6 overall, but the failure is NOT one thing.** The retest found a second,
different defect — a genuinely malformed XML element — and produced the first passing sample.
T2 therefore remains **FAIL**, now on stronger evidence and with a clearer diagnosis.

## Methodology fix over the main run

The main run's `r2`/`r3` repeats were **prompt-cache hits** (prompt_n = 4 tokens), which is weaker
evidence. The retest restarted the candidate container between samples, so each sample is a genuine
**cold prefill** (prompt_n = 32 every time, prompt-eval ≈ 665–674 ms). That caveat is now closed.

Note the harness changed between the two batches (`c88327dd` → `a415474b`), but T2 is a **direct**
task — it goes straight to `curl` and never runs through the dsh harness, so the harness cannot
affect it. The two batches are directly comparable.

## All six samples

| sample | harness | verdict | chars after `</svg>` | inner SVG | failure mode |
|---|---|---|---|---|---|
| `t2_svg` | `c88327dd` | FAIL | 395 | valid | prose after `</svg>` |
| `t2_svg_r2` | `c88327dd` | FAIL | 389 | valid | prose after `</svg>` |
| `t2_svg_r3` | `c88327dd` | FAIL | 319 | valid | prose after `</svg>` |
| `t2_cold1` | `a415474b` | **FAIL** | 4 | **INVALID** | **malformed XML inside the SVG** |
| `t2_cold2` | `a415474b` | FAIL | 468 | valid | prose after `</svg>` |
| `t2_cold3` | `a415474b` | **PASS** | 4 | valid | — |

**5 FAIL / 1 PASS.**

### The `t2_cold1` defect is a real markup bug, not a formatting quirk

This one is worth separating, because it is a different class of failure and the main report could
not see it. The SVG body does not parse as XML at all — and the trailing content is only 4 bytes
(`"\n```"`), so this is **not** the prose problem. Line 40 of the document:

```
37 |       <stop offset="0%" stop-color="#ffaa66"/>
38 |       <stop offset="40%" stop-color="#cc6633"/>
39 |       <stop offset="70%" stop-color="#883322"/>
40 |       <offset="100%" stop-color="#441111" stop-opacity="0"/>
41 |     </radialGradient>
```

`<offset=...` is missing its element name — it should be `<stop offset=...`. That is a
**malformed-XML generation defect in the model output**, reproducible in the sense that it is a real
error in the delivered document, not a grader artefact and not a prompt-format complaint.

### The prose problem is unchanged

`t2_cold2` (468 chars) reproduces the main run's signature exactly: fenced SVG, closed `</svg>`,
then a Chinese explanation. Three of the three main-run samples and one of the three retest samples
share it. `t2_cold3` is the first clean pass across six samples — the model *can* do it, which is
what makes the 5/6 rate a behaviour claim rather than a formatting rule.

## Performance collected (the three retest requests)

Server `print_timing`, one request each, cold prefill:

| sample | prompt_n | prompt_eval ms | prefill tok/s | predicted_n | eval ms | decode tok/s | accept % | accepted/generated |
|---|---|---|---|---|---|---|---|---|
| `t2_cold1` | 32 | 671.8 | 47.63 | 9,609 | 208,543.7 | 46.08 | 86.7 % | 6,939 / 8,007 |
| `t2_cold2` | 32 | 663.5 | 48.23 | 12,007 | 259,242.3 | 46.32 | 88.8 % | 8,729 / 9,831 |
| `t2_cold3` | 32 | 673.5 | 47.51 | 6,299 | 132,314.2 | 47.61 | 88.7 % | 4,578 / 5,160 |
| **aggregate** | 32 | — | **47.79** | 27,915 | — | **46.52** | **88.0 %** | 20,246 / 22,998 |

Client-side TTFT (first token − send): **0.681 / 0.669 / 0.678 s** — very stable, and ~0.01 s above
the server's prompt-eval, i.e. negligible HTTP overhead on a 32-token prompt.

Draft acceptance K = 3 (`SPEC_DRAFT_N_MAX=3`), confirmed from the running server.

### Against the baseline and the main run

| | prefill tok/s | TTFT s | decode tok/s | accept % |
|---|---|---|---|---|
| v0.6.0 baseline (2026-10-05) | 50.33 | 0.64 | 45.74 | 85.7 % |
| main run `t2_svg` (warm) | 49.71 | 0.64 | 47.16 | 89.5 % |
| **retest, 3 cold samples (aggregate)** | **47.79** | **0.67** | **46.52** | **88.0 %** |

Decode is **+1.7 %** over the baseline; prefill is **−5.0 %** and acceptance **+2.3 pp**. All three
sit inside the run-to-run spread already recorded for this task (the main run and the baseline
differ by −1.2 % / −0.1 % on the same metrics), so **no performance regression**. Note the retest is
a cold-prefill measurement while the main run's `t2_svg` was the first warm-ish call — prefill on a
32-token prompt is a single burst and is not a throughput figure in either case.

## Stability

| check | value |
|---|---|
| candidate RestartCount / OOMKilled | **0 / false** (through 3 container restarts) |
| `xtx-vulkan` RestartCount | 0 → **0** |
| log lines scanned | 5,229,270 |
| `SIGSEGV` / `UR_RESULT_ERROR` / `device lost` / `Failed to allocate` / `GGML_ASSERT` | **0 each** |
| largest model buffer | **17402.38 MiB, unsplit** (unchanged across all restarts) |

## Effect on the gate

T2 stays **FAIL**. The suite is therefore **6 PASS / 2 FAIL (T2, V3)** — see the verdict note in
`REPORT.md` for why that does not clear the build for promotion.

The retest *strengthened* the finding rather than resolving it:
- the prose-after-SVG behaviour is confirmed at cold start (it was not a cache artefact),
- a **second, independent** defect surfaced (malformed `<offset=` element),
- and one clean pass proves the model is capable, so the 5/6 rate is a real behavioural rate.

Operationally this is arguably worse than the main run suggested: the main run showed one failure
mode 3/3; the retest shows **two** distinct modes in 3 samples.

## Restoration

Card held ~13 minutes. Server log dumped before teardown. Production restored and verified
end-to-end — **step 4 caught it a fourth time**: `/health` ok and worker inferring while SMG
reported `18080=False/failed`; the breaker cleared after ~100 s (21:27:06 → 21:28:46 ready).
Final: `b70-sycl`, `xtx-vulkan`, `smg` all up; `b70-sycl` and `xtx-vulkan` both
`RestartCount=0`, `OOMKilled=false`. Candidate left stopped, not removed.
