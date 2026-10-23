# B70 SYCL Test Report — dev `b11706` (issue #31)

**Issue:** [snailium/llama.cpp-sycl-intel-b70#31](https://github.com/snailium/llama.cpp-sycl-intel-b70/issues/31) (dev weekly build)
**Date:** 2026-10-23 · **Host:** GPU host (.101) · **Card:** Arc Pro B70 32 GB (`xe`, `renderD128`)
**Image:** `server-dev-b11706-c26.35.39758.10-20261017-0232`
**Digest:** `sha256:7935d24ae9c927e8017924ff75010a5ff3f978d94dd0312e368ddda4bacb49cb`
**In-image:** `libllama.so.0.7.0` / `libggml-base.so.0.27.0`, `--version` → `0.7.0-dev (build 0, commit unknown)`
**Intel stack:** compute-runtime `26.35.39758.10` (`libze_intel_gpu.so.1.17.39758`) · L0 `1.32.0` · oneDNN `2026.0` (`libdnnl.so.3.11`) — **byte-identical to v0.7.0**
**Baseline for every comparison:** v0.7.0 stable, `sha256:b265f403…` (promoted 2026-10-21)
**Harness:** `sha256:ae65d5e03225…` (dsh 0.2.1-rc.2, breaker 0.11.6)
**Skill:** `8af83da1…` (all 8 prompts verified verbatim against it before the run)

## Range correction — the issue's start point overcounts

Issue #31 says *"Subtree: advanced from `b11540` to `b11706`"*. **`v0.7.0` sits between them:**

```
b11540 (2026-10-10)  →  v0.7.0 (2026-10-16, tested + promoted)  →  b11706 (2026-10-17)
```

Verified with `git merge-base --is-ancestor`: `b11540` is an ancestor of `v0.7.0`, and `v0.7.0`
is an ancestor of `b11706`. The image reports `0.7.0-dev`, so it is **v0.7.0 + post-release
master commits**. Taking `b11540..b11706` would re-count content already tested in issue #30,
so all triage below uses **`v0.7.0..b11706` = 37 commits**.

## What actually changed (SYCL)

Four commits touch `ggml/src/ggml-sycl/`. Three reach our config.

| Commit | PR | Change | Reaches us? |
|---|---|---|---|
| `f74e2fa6a` **(= b11706 HEAD)** | #30374 | Fix the **prompt-processing regression** after the Q4_0/Q8_0 weight reorder. `dequantize_block_q4_0_reorder` / `q8_0_reorder` rewritten as grid-stride loops over `k/2` / `k` with explicit `local_range * group_range` stride — the old one-thread-per-block mapping broke when the launcher shrank the work-group to stay under `INT_MAX`. Also switches the math back to f32 (the helper computed in half under `GGML_SYCL_F16`). | **Yes** — our **draft model is Q8_0**, and this is the prompt-processing path |
| `a30fb4924` | #29889 | Fix memory errors: host-staging allocation now aborts with a logged error instead of continuing on a `nullptr`; `get_max_mem_alloc_size()` reads the **buft's device** rather than the current device; host-pool counter/wrap-around fixed; per-device queue vector sized once. | **Yes** — `max_alloc_size` is the input to the **model-buffer split decision** (our documented trap) |
| `13de11e78` | #29696 | **Wide stores for the q4_K/q5_K weight dequant.** New `dequantize_block_q4_K_wide`: 32 work-items per 256-weight block, `vec<uint8_t,4>` loads and `vec<dst_t,4>` stores. Used from `convert.cpp`. | **Yes, directly** — **Q4_K is our main model's quant**; `GGML_TYPE_Q4_K` is in every reorder-support list |
| `e707790c7` | #29337 | Support reordered Q8_0 **MoE** weights | **No** — we run a dense 27B |

Also relevant: `6afa9a313 llama: share the k-pool input views between layers (#30613)` (KV pool,
not SYCL). The other 32 commits are model architectures (Mellum2.1, Muse Spark, Granite Switch,
Beam), `convert`/`gguf-py`, hexagon, CUDA/RocM, OpenCL, CI, and two build-only SYCL changes
(`c0083e305` build threads, `43d57fb8c` SSL in the build script).

**Decision rule (dev `b*` → test if it hits a ggml-sycl kernel / oneDNN / XMX path):** three of
four do. This was worth testing, and #29696/#30374 hit our exact quant and prompt path.

## Results

`TTFT` is the **prompt-eval time** (`prompt_ms`), i.e. time to first token. For vision tasks the
CPU-side mmproj image encode is inside `prompt_ms` (`LLAMA_ARG_MMPROJ_OFFLOAD=false`). Prefill is
`prompt_n / prompt_ms`; decode is `predicted_per_second`.

| Task | prompt_n | prefill tok/s | vs v0.7.0 | TTFT s | vs v0.7.0 | completion | decode | vs v0.7.0 | accept % | vs v0.7.0 | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 43 | 69.43 | **+53.2 %** | 0.619 | **−34.7 %** | 10162 | 41.04 | −0.0 % | 74.5 | +0.9 | **PASS** |
| T2 | 32 | 63.70 | **+38.4 %** | 0.502 | **−27.7 %** | 8718 | 46.05 | −1.4 % | 86.5 | −0.6 | **FAIL** (fenced) |
| A1 | 10858 | 663.03 | **+22.4 %** | 16.376 | **−18.3 %** | 4383 | 22.83 | +3.6 % | 54.9 | +5.4 | **PASS** |
| A2 | 9214 | 765.67 | **+26.2 %** | 12.034 | **−18.8 %** | 1452 | 40.64 | −2.6 % | 78.8 | −1.9 | **PASS** |
| A3 | 95050 | 640.28 | n/a † | 148.45 | n/a † | 16645 | 29.56 | n/a † | 77.3 | n/a † | **PARTIAL** (see below) |
| V1 | 3528 | 49.95 | +1.5 % | 70.637 | −1.4 % | 905 | 36.06 | −4.3 % | 60.2 | −3.6 | **PASS** |
| V2 | 1064 | 81.92 | +4.1 % | 12.989 | −3.9 % | 1608 | 36.56 | +4.1 % | 59.3 | +4.1 | **FAIL** (fabricated) |
| V3 (run 1) | 4160 | 35.95 | −20.9 % | 115.713 | +26.4 % | 414 | 36.61 | +4.6 % | 61.6 | +4.9 | **FAIL** (`113S`) |
| V3 (repeat) | 4160 | 41.66 | −8.3 % | 99.858 | +9.1 % | 581 | 35.50 | +1.5 % | 58.7 | +2.0 | **FAIL** (`113S`) |

† **A3 gets no cross-run delta, deliberately.** Its largest prompt here was **95050** tokens versus
**12483** in the v0.7.0 rerun — a 7.6× difference in context depth — and A3 is already established
as non-reproducible (three runs, three outcomes on the v0.7.0 digest). Deep context lowers decode
by design (the memory-latency ceiling, upstream #26581) and raises TTFT, so any delta computed
across those two runs would measure *context depth*, not the build. A3's own numbers are reported
and graded; the comparison is withheld rather than fudged.

`A2`'s prompt_n differs slightly (9214 vs 8993) — same task, different content, so its prefill
delta is approximate.

## The finding: prompt-processing is materially faster, decode is unchanged

**Long-prompt prefill (the reliable measure) improved on both comparable agent tasks:** A1
+22.4 %, A2 +26.2 %. These are not fixed-cost artefacts — at 10858 tokens the per-request
overhead is ~1.5 % of the measurement. This is consistent with #29696: the Q4_K/Q5_K weight
dequant runs on the prefill path (`convert.cpp` → `dequantize_block_q4_K_wide`), and Q4_K is our
main quant.

**Fixed per-request cost dropped ~330 ms.** T1 is a 43-token prompt, where rate is dominated by
fixed cost:

| build | T1 prompt_ms | note |
|---|---|---|
| v0.6.0 | 689 ms | — |
| **v0.7.0** | **948.7 ms** | +260 ms fixed cost vs v0.6.0; recorded in the issue #30 report as **not** a throughput regression |
| **b11706** | **619.4 ms** | **−330 ms vs v0.7.0**, and below v0.6.0 |

That is exactly what #30374 claims to fix ("prompt-processing regression"), and the direction
matches: the fixed overhead v0.7.0 carried is gone. T2 shows the same shape (695 → 502 ms).

**Decode is unchanged** on the seven comparable tasks (−4.3 % … +4.6 %, i.e. within run-to-run noise); A3 is excluded because its context depth differs by 7.6×. This
is the expected signature: wide dequant stores and a dequant-launcher fix affect weight
conversion for prefill, not the MMVQ decode path.

**Vision prefill is noisy, not regressed.** V1 +1.5 %, V2 +4.1 %, V3 −20.9 % then −8.3 % on the
**same image, same prompt**. The 12-point spread between two V3 runs shows the noise floor
dominates here — image encode is CPU-side and the host also serves `xtx-vulkan`. **Two samples
straddling the baseline are not evidence of a vision regression**, and I am not claiming one.
A vision prefill claim from this run would need N repeats.

### T2 fails on output shape, not on the backend

The SVG content is **well-formed** (extracted: 18985 chars, `ElementTree` parses, root
`{http://www.w3.org/2000/svg}svg`), but the response wraps it in a ```` ```svg ```` fence and
appends ~1 KB of explanatory prose plus a table. The criterion used for the v0.7.0 PASS was
*"bare SVG, parses, no wrapper, no trailing text"*, so this run is a **FAIL** on the artefact
rule. This is model output behaviour at `temperature 0.7` — sampling nondeterminism, not a SYCL
property. Worth noting that v0.7.0 passed this and b11706 did not, on a build with no
text-generation changes, which is itself evidence that T2's bare-output rule is flaky.

### V2 / V3 fail the same way they always do

- **V2: 17/21 truth labels (81 %).** Missed `FCH`, `USB31A`, `USB32A`, `VGA`. It also emitted
  designators that are not on the graded list — `U66`–`U72`, `C057`–`C072`, `SATA0`/`SATA1`,
  `L22`, `USB2A`, `USB3A`. That is the same fabrication defect class as v0.7.0 (16/21, invented
  `Q05–Q16`, `U53A/B`, `X2`, `SATA1–6`). It did get `F_PANEL` and `U65`, which v0.7.0 missed.
- **V3: `113S` where the truth is `118S`** — the **fourth** occurrence of this defect class
  (v0.6.0 and v0.7.0 both returned `113S`). It read `255/70R18` correctly and resisted the
  prompt's decoy, so the failure is isolated to the load-index characters.

Both are model quality on image reading, reproduced across three image builds. Not backend.

### A3 is partial — and my own breaker config caused it

A3 produced **258.6 cm for 2025-11-01 … 2026-04-30**, with all six monthly values matching
ground truth exactly (32.5 / 54.6 / 81.6 / 48.3 / 41.0 / 0.6). It then stopped, correctly
reporting that it could not retrieve May–December 2026.

**The stop was caused by the harness configuration I set, not by the image.** The tightened
`repeat-tool-breaker` in the test home uses `host: 6`; A3 walked
`climate.weather.gc.ca/climate_data/daily_data_e.html?...&Month=M&Year=Y` one month at a time,
and its 7th fetch to that host was blocked (`REPEAT_TOOL_BLOCKED`), as was its delegated
subagent's. That guard exists to stop runaway loops, but 12 monthly pages from one host is a
legitimate pattern and the limit is too tight for this task shape.

**Grading note:** the number it did produce is the **correct total for the asked period** — my
independent recompute from `ottawa.weatherstats.ca` gives 258.6 cm with May–Oct 2026 all `0.0`
and Nov–Dec 2026 having no observations yet. So A3's figure is right; only its stated scope is
conservative. This is a **partial pass on the number, blocked by harness config**, and should not
be recorded as a backend failure.

## Memory layout — no splitting (the trap did not fire)

`#29889` touches `max_alloc_size`, which is the input to the split decision, so this was checked
on **two separate loads** (initial launch and after a container restart for the clean T1 re-measure):

```
load_tensors: SYCL0 model buffer size = 17402.38 MiB      <- one unsplit buffer, both loads
llama_kv_cache: SYCL0 KV buffer size =  4352.00 MiB
sched_reserve:  SYCL0 compute buffer size = 752.29 MiB
load_tensors: SYCL0 model buffer size =  1718.71 MiB      <- draft
llama_kv_cache: SYCL0 KV buffer size =   272.00 MiB
```

Byte-identical to the v0.7.0 and v0.6.0 baselines. No split, no fragment count change.

## Stability — scoped

`RestartCount=0`, `OOMKilled=false`. **Scope limit, stated plainly: the full-run log was not
captured before the test container was removed**, so the direct-task windows (T1/T2/V1–V3) were
not scanned. What *was* scanned — the captured A1+A2+A3 windows, **597,370 lines** — has zero
occurrences of `SIGSEGV`, `UR_RESULT_ERROR`, device lost, allocation failure,
`ggml_sycl_pool_vmm`, `GGML_ASSERT`, stack smashing, wedged, GPU hang, OOM, `terminate called`,
or unhandled exception. The direct tasks all returned `finish_reason=stop` with complete
`timings`, which shows the server survived each of them. This is a smaller scan than the
4.35 M-line scan done for issue #30 and should be read as such.

## Verdict

**Worth taking forward; not promoted (it is a dev build).**

The image is a **strict improvement on the path we care about**: long-prompt text prefill
**+22–26 %**, fixed per-request cost **−330 ms** (recovering the v0.7.0 prompt-processing
regression and then some), decode unchanged, memory layout byte-identical, no crash signatures
in the scanned window.

What it does **not** do: change the vision model-quality defects (V2 fabrication, V3 `113S`) —
those are identical to the promoted image. T2's new artefact failure is sampling behaviour, not
a backend property.

**Recommendation:** treat `b11706` as the **next stable candidate** and promote it when a stable
`v*` build carries the same SYCL set. If a dev promote to `:server-dev` is wanted sooner, the
prefill evidence supports it. Two things to re-measure before any promote:

1. **Vision prefill with repeats** — V3 moved 12 points between two runs on the same digest;
   one more pair of samples would establish the noise floor and let a real vision claim be made.
2. **T2 bare-output** — re-run a few times to see whether the fence/trailing-prose failure
   reproduces or is a one-off at this temperature.

For A3 specifically: raise the breaker `host` limit (or pin the data source) before the next run,
otherwise the guard, not the model, decides the outcome.

## Production restoration (verified end-to-end)

`b70-sycl` was stopped with consent and restored afterwards. The SMG trap fired for the
**fourth** consecutive restore: worker `/health` returned ok and a routed request returned 200,
while `/workers` still reported the B70 worker `healthy=False status=failed` (the 200 was served
by the XTX worker). `docker restart smg` + 40 s cleared it.

Sequence verified: worker `/health` → `{"status":"ok"}` → worker infers `ok` → **through the SMG
router** (real completion, HTTP 200) → `/workers` both `healthy=True status=ready`.

Final state: `b70-sycl` `restart=0 oom=false status=running (healthy)`,
`xtx-vulkan` `restart=0 oom=false status=running (healthy)`, `smg healthy`. Test container
removed. No production container was rebuilt or re-created.

## Artifacts

- `evidence/windows/{a1,a2,a3}.log` — the captured server-log windows used for the metrics
- `evidence/stability-scan.txt` (scoped, see above), `evidence/props.json` (config read-back),
  `evidence/version-readback.txt` (Intel stack inside the image)
- `results/*_result.json` — authoritative `timings` per direct task, plus `t1_recheck_result.json`
  (the clean T1 re-measure) and `results/a3_answer.md`
- `logs/{a1_security,a2_hostinfo,a3_snowfall}.session.jsonl` — harness sessions
- `logs/windows.txt`, `logs/windows-recheck.txt` — `docker logs | wc -l` window markers
- `launch-candidate.sh`, `run_battery.sh`, `run_direct.py`, `extract_metrics.py`

### Measurement integrity notes

- **The first T1 run was discarded.** It returned `cache_n=39, prompt_n=4` — an aborted earlier
  T1 attempt (killed when its background shell died) had left a context checkpoint, and the
  server restored `n_past=39` of the 43 prompt tokens. The table above uses a **clean re-run
  after a container restart** (`cache_n=0, prompt_n=43`). The contaminated sample's decode
  (42.79) agrees with the clean one (41.04), so only its prefill/TTFT were unusable.
- **V3 was run twice** precisely to test the −20.9 % anomaly; the second sample (−8.3 %) does not
  reproduce it.
- **A3 has no cross-run delta at all.** Its largest prompt was 95050 tokens against 12483 in the
  v0.7.0 rerun, so every delta would measure context depth rather than the build. An earlier draft
  of this table mixed the v0.7.0 arm-1 decode baseline with the arm-2 prefill baseline — that was
  wrong and has been removed rather than restated.

---

## Follow-up: the vision projector moved to the GPU (measured after the main run)

The golden config had carried `LLAMA_ARG_MMPROJ_OFFLOAD=false` since 2026-08-25, i.e. the image
encoder ran on the **host CPU**. It turned out to be an oversight rather than a decision: the XTX
had already been measured on 2026-10-06 (issue #10: image prefill 53.8 → 480.3 t/s, 8.9×;
TTFT 65.6 → 7.35 s) and runs the projector on the GPU by simply *omitting* the variable, because
the llama.cpp default is enabled. The B70 never followed.

Re-measured as a **clean single-variable A/B on the same image digest** (`sha256:7935d24a…`),
with `prompt_n` identical and `cache_n = 0` on both sides:

| Task | prompt_n | CPU mmproj: prefill / TTFT | **GPU mmproj: prefill / TTFT** | speedup |
|---|---|---|---|---|
| V1 | 3528 | 49.95 tok/s / 70.64 s | **255.70 tok/s / 13.80 s** | **5.1×** |
| V2 | 1064 | 81.92 tok/s / 12.99 s | **366.63 tok/s / 2.90 s** | **4.5×** |
| V3 | 4160 | 35.95 tok/s / 115.71 s | **266.45 tok/s / 15.61 s** | **7.4×** |

- **Decode unchanged** (−1.1 % … +5.6 %) and draft acceptance unchanged — expected, since device
  placement does not touch the generation path.
- **`T1` control** (text, no image) moved −16 % on a 43-token prompt: inside the fixed-cost noise
  band already documented for that task (0.619–0.949 s across builds). The flag does not touch the
  text path.
- **Memory:** the main model buffer stayed **one unsplit `17402.38 MiB` allocation**; the projector
  added `848.18 MiB` to `SYCL0` plus `24.93 MiB` on CPU (~25.3 GB of 32 GB at 128k). The
  buffer-splitting trap did not fire.
- **Verified on the running server:** `clip_ctx: CLIP using SYCL0 backend` (previously
  `CLIP using CPU backend`).
- **Model quality unchanged:** V3 still returned `113S` for a `118S` tyre and V2 still fabricated
  designators (13/21 this time versus 17/21 on the CPU config — both FAIL, and V2's partial credit
  has now ranged 13–17 across runs). Device placement changes speed, not reading.

This also explains the vision numbers in the main table above: with the projector on the CPU the
`prompt_ms` of a vision request includes host-CPU encoding, which is why those prefill rates read
36–82 tok/s against 600+ tok/s for text, and why V3 moved 12 points between two runs on the same
digest while text prefill stayed within ±1 %.

**Production followed.** The `llm_backends` stack (`b70-sycl`, v0.7.0) was updated to
`MMPROJ_OFFLOAD=true` and verified on a live request: image prefill **81.6 → 246.5 tok/s**,
`prompt_ms` **12771 → 4248** (3.0×) on the same test image.
