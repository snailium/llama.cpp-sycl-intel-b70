# B70 SYCL Test Report — Intel Arc Pro B70 (32 GB) · `server-dev-b11540-c26.35.39758.10-20261010-0349`

**Date:** 2026-10-11 · **Backend host:** `gpu-host` `.101` (B70) · **Harness host:** `control-host` `.90`
**Backend:** llama.cpp `b11540` SYCL / oneAPI (dev weekly build)
**Model:** `/models/Qwen3.8-27B-Q4_K_M.gguf` (Q4_K_M) + `mtp-Qwen3.8-27B-Q8_0.gguf` (MTP3) + Q8_0 mmproj
**KV:** main + draft `q8_0` · **ctx:** 131072 · **flash-attn:** on · **n_parallel:** 1
**Speculative decoding:** `draft-mtp`, **K = 3** (`SPEC_DRAFT_N_MAX=3`, `P_MIN=0.1`)

| | |
|---|---|
| **Backend image digest** | `sha256:8bfbe3755396d679b6691c9c79d156343ca176c4354e48897c201722b9b3f67c` |
| **Harness image digest** | `sha256:c88327dd3686fa75b0195481a7a045e2f899345b8c79f54a6b23a8d57ddf29e5` (`dsh:latest`, `0.2.0-rc.2`) |
| **Skill sha256** | `8af83da14abfa1408204e2eff762470c8dba0e8e4c5dae5893ee1656d1546a53` (backend-test-suite, read at run time) |
| **Golden config sha256** | `1f174ae9c8a2c69c10ebdda556ff715ac452827f35eb08172c658a31e3a41c6a` (`docs/GOLDEN-CONFIG.md` @ `origin/main` `1a7e84e2`) |
| **Intel stack** | compute-runtime `26.35.39758.10` · IGC `2.41.5` · L0 loader `1.32.0` — **byte-identical to the v0.6.0 baseline** |
| **Comparison baseline** | `server-c26.35.39758.10-v0.6.0-20261005-1957` (`sha256:b5799bf3f66b…`, the 2026-10-05 issue #26 run) |

**Sampling:** inherited from the backend — read back from `/props`, **not** from the launch intent:
`temperature 0.7` · `top_p 0.80` · `top_k 20` · `min_p 0.0` · `presence_penalty 1.5` ·
`frequency_penalty 0.0` · `repeat_penalty 1.0`, `n_ctx = 131072`. All six sampling env vars were
accepted (this build is far past the `>= b11078` floor).

**Two request fields sent, and only these:** `chat_template_kwargs.enable_thinking=false`, and
`max_tokens=32768` for T1/T2/V1–V3. `stream: true` on T1/T2 is transport, not sampling.

**Trim auto-tune: ON** (`DSH_TRIM_AUTO_TUNE=1`). The tuner printed
`context-trim: auto compaction tune: Retuned compaction-basic …` and the persisted row in
`profiles/headless_lc/cordis.patch.yml` carries `headroomTokens: 9831`
(= `(131072 − 16384) − floor(0.8 × 131072)` — arithmetic verified, not assumed). Effective
compaction trigger **80 %** of the window. It also wrote `tool-result-pruner.thresholdChars: 32768`.

**Capture mode:** `DEBUG_FLAG=-v`. Direct tasks are read from `slot print_timing`; agent tasks are
aggregated from that task's own `print_timing` blocks, sliced by a per-task **request-index window**
(`req_before`/`req_after` recorded around each task), never by a `docker logs --since/--until`
timestamp window. The candidate container log reached **2,589,983 lines**.

---

## Results Summary

Agent rows aggregate **that task's own calls**: `prompt_tok` is the **largest** call's prompt,
TTFT is the **first** call's prompt-eval time, completion is the task total, decode is total
completion over total generation time, and acceptance is summed over the task's calls. Direct
tasks are one request each, so their rows are exact per-request figures.

| Task | Status | prompt_tok | prefill tok/s | TTFT s | completion_tok | decode tok/s | accept % | Notes |
|---|---|---|---|---|---|---|---|---|
| T1 | **PASS** | 43 | 61.89 | 0.69 | 4841 | 45.01 | 81.9 % (3440/4200) | HTML parses, balanced, `<html>/<head>/<body>`, ends `</html>`, `finish_reason=stop` |
| T2 | **FAIL** | 32 | 49.71 | 0.64 | 8758 | 47.16 | 89.5 % (6381/7128) | **SVG inside a fence, then ~395 chars of prose after it → the delivered content does not parse as XML.** Reproduced 3/3 — see Finding 2 |
| A1 | **PASS** | 12699 (largest) | 518.85 | 0.78 (first) | 3446 | 23.42 | 54.2 % (2126/3921, 16 calls) | Repo acquired by the agent itself; 12 findings (1 H / 5 M / 6 L), each with location, risk, reason, fix; spot-checks matched the real source |
| A2 | **PASS** | 8898 (largest) | 511.21 | 0.80 (first) | 1836 | 41.27 | 80.9 % (1298/1605, 7 calls) | Valid JSON, values gathered (6 shell calls incl. `ls /dev/dri`); host fields correct. Two observations — see Finding 4 |
| A3 | **FAIL** | 57069 (largest) | 346.24 | 0.73 (first) | 19844 | 32.02 | 90.7 % (14265/15726, **341 calls**) | **Degenerate loop on a 404 URL; no answer produced.** Terminated early — see Finding 3 |
| V1 | **PASS** | 3528 | 49.05 | 71.93 | 922 | 35.21 | 56.4 % (579/1026) | 莉拉 / LV 700 / 千律-popup / LV6 / XR2 / 850 % / −def 8 s / 400 % / 减防75 % / 沉默 — all correct except the skill *name* `千律` omitted |
| V2 | **PASS** (marginal) | 1064 | 79.41 | 13.40 | 2200 | 36.08 | 58.0 % (1397/2409) | 13/21 ground-truth labels; no invention *inside* the ground-truth set; several asserted labels are not on the board |
| V3 | **FAIL** | 4160 | 45.14 | 92.16 | 714 | 33.32 | 51.9 % (434/837) | Read **255/70R18** + **M+S** + 3PMSF correctly, but misread the load/speed index as **T103** (truth **118S**) and asserted an unreadable brand as "BFGoodrich All-Terrain T/A KO2" |

**TTFT definition.** The value above is the server's prompt-eval time, which is what the archived
baselines used. The client-side TTFT (`first token − send`, the skill's definition) was **1.32 s**
(T1) and **0.93 s** (T2) — 0.6 s and 0.3 s above prompt-eval, i.e. HTTP + template overhead.

### Comparison against the previous baseline (`v0.6.0`, 2026-10-05)

| Task | prefill tok/s | Δ | TTFT s | Δ | decode tok/s | Δ | accept % | Δ |
|---|---|---|---|---|---|---|---|---|
| T1 | 62.37 → 61.89 | −0.8 % | 0.69 → 0.69 | ±0 | 42.18 → 45.01 | **+6.7 %** | 73.7 → 81.9 | +8.2 pp |
| T2 | 50.33 → 49.71 | −1.2 % | 0.64 → 0.64 | ±0 | 45.74 → 47.16 | +3.1 % | 85.7 → 89.5 | +3.8 pp |
| A1 | 580.37 → 518.85 | −10.6 % | 1.06 → 0.78 | −26 % | 22.91 → 23.42 | +2.2 % | 52.8 → 54.2 | +1.4 pp |
| A2 | 595.32 → 511.21 | −14.1 % | 0.75 → 0.80 | +6.7 % | 40.58 → 41.27 | +1.7 % | 76.5 → 80.9 | +4.4 pp |
| A3 | 527.50 → 346.24 | **n/m** | 0.74 → 0.73 | ±0 | 32.22 → 32.02 | −0.6 % | 74.0 → 90.7 | **artifact** |
| V1 | 48.10 → 49.05 | +2.0 % | 73.35 → 71.93 | −1.9 % | 34.55 → 35.21 | +1.9 % | 56.0 → 56.4 | +0.4 pp |
| V2 | 78.71 → 79.41 | +0.9 % | 13.52 → 13.40 | −0.9 % | 36.10 → 36.08 | −0.1 % | 58.8 → 58.0 | −0.8 pp |
| V3 | 45.01 → 45.14 | +0.3 % | 92.42 → 92.16 | −0.3 % | 32.70 → 33.32 | +1.9 % | 50.9 → 51.9 | +1.0 pp |

**No performance regression.** Decode is flat-to-better on every task that completed; the largest
moves are within run-to-run noise (T1 +6.7 % is 45.01 vs 42.18 tok/s on a 4841-token generation).
The prefill drops on A1/A2/A3 are **not** claimed as regressions: prefill on an agent task tracks
*which prompt length the largest call happened to reach*, which differs run to run. **A3's prefill,
decode and 90.7 % acceptance are all meaningless** — the task looped, so its aggregate describes
341 repetitions of one failing call, not a workload. A3's row is reported for completeness only.

**A2's completion token count (1836 vs 372)** is a task-shape difference: this run's A2 wrote a
much longer JSON document plus a summary table.

### Memory-splitting trap — checked, clear

```
load_tensors:   CPU_Mapped model buffer size =   682.03 MiB
load_tensors:        SYCL0 model buffer size = 17402.38 MiB
```

The largest buffer is **unsplit at 17402.38 MiB — byte-identical to the b11368 and v0.6.0
baselines**. No compute-runtime max-allocation split occurred, so the decode figures above are
comparable on memory grounds and none of the deltas is the split-buffer artefact.

### Configuration confirmed from the running server

`/props` read back; every golden value accepted:

```
n_ctx = 131072
  temperature = 0.7 · top_p = 0.80 · top_k = 20 · min_p = 0.0
  presence_penalty = 1.5 · frequency_penalty = 0.0 · repeat_penalty = 1.0
```

Draft KV confirmed from the server log (the `LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_K/_V` name trap):

```
spec common_specu: - gpu_layers=-1, cache_k=q8_0, cache_v=q8_0, ctx_tgt=yes, ctx_dft=yes, devices=[default]
spec common_specu: - n_max=3, n_min=0, p_min=0.10, n_embd=5120, backend_sampling=1
```

The candidate container's environment was diffed against the golden list: **identical** apart from
`ONEAPI_ROOT`, which the image sets itself.

---

## Stability

| Check | Value |
|---|---|
| Candidate `b70-dev-test-b11540` RestartCount / OOMKilled | **0 / false** (launch → end) |
| `xtx-vulkan` RestartCount | 0 before → **0 after** (no leak outside the B70) |
| `b70-sycl` (production) RestartCount | 0 → 0 |
| Log lines scanned | 2,589,983 |

**Zero crash signatures.** Explicit scan, each count = 0: `SIGSEGV`, `segmentation fault`,
`UR_RESULT_ERROR`, `device lost`, `out of memory`, `allocation failure`, `ggml_sycl_pool_vmm`,
`Failed to allocate`, `stack smashing`, `Aborted`, `GGML_ASSERT`. No `xe`/GPU errors in `dmesg`.

The candidate container was **stopped, not removed** (`Exited (0)`), so it remains available for
post-mortem.

---

## Findings the numbers alone would hide

### 1. Three sessions were spawned for one issue event — and two ran the same test concurrently

The webhook delivered issue #29 **three times** inside ten minutes, creating three sessions:

All three name the same issue, the same action (`reopened`) and the same image tag:

| delivery | session | started | instructions source | outcome |
|---|---|---|---|---|
| `0d957a60-c533-11f1` | `webhook-c0210f48` | 01:17 EDT | **embedded (ENOENT)** | died at 01:17:48 |
| `b23e3020-c533-11f1` | `webhook-8b4c84c5` | 01:22 EDT | **embedded (ENOENT)** | stopped by the user at 01:36; it had already stopped production and launched the candidate |
| `de6888c0-c534-11f1` | **this run** (`webhook-41a6c201`) | 01:30 EDT | `docs/AGENT-TEST-PROMPT.md` | took over after the user stopped the duplicate |

This is the process finding of the run. The earlier delivery read the instruction file as
**ENOENT** and fell back to the embedded copy, whose first step points at `docs/GOLDEN-CONFIG.md`
*relative to the workspace root* — a path that does not exist (the repo documents live under the
checkout, and the `dev` branch does not carry them at all). That session spent 14 steps hunting for
the file before reconstructing the golden from `origin.git`. The current instructions fix this, but
**nothing prevents a repeat**: the duplicate-delivery path that produced two concurrent agents on
one single-GPU card is still open. One card cannot host two inference containers, so the second
session is not merely wasteful — it is a correctness hazard, and this run only avoided
contaminating both by stopping one of them before any measurement began.

Its launch also attached the candidate to a user network (`--network llm_backends_default`), which
left `docker port` empty and `:18082` unreachable from `.90`. This run relaunched with the golden's
own form (default bridge + `-p 18082:8080`) and confirmed `/v1/models` 200 from the harness host
before measuring anything.

### 2. T2 fails its structural criterion, reproducibly, and it is a *delivery* failure, not a markup one

Three independent samples were taken because the first one failed (the repeat was pre-declared, all
three are reported, none was discarded):

| sample | finish_reason | canonical grader | inner `<svg>` | trailing prose after `</svg>` |
|---|---|---|---|---|
| `t2_svg` | stop | **FAIL** | valid, `viewBox="0 0 1000 800"` | 395 chars |
| `t2_svg_r2` | stop | **FAIL** | valid, `viewBox="0 0 1200 800"` | 389 chars |
| `t2_svg_r3` | stop | **FAIL** | valid, `viewBox="0 0 1200 900"` | 319 chars |

All three behave identically: the model emits a correct, well-formed SVG inside a ```svg fence,
closes the fence, and then appends a Chinese prose explanation. The grader's fence-stripper is
anchored at end-of-string, so trailing prose leaves the content starting with ```svg and the XML
parse fails at line 1.

**Both archived baselines passed this task cleanly** — `2026-10-04-b11368-dev/t2_svg.svg` and
`2026-10-05-issue26-v060-stable/t2_svg.svg` each contain a bare `<svg>` with **0 characters after
`</svg>`**. So the failure mode is new and consistent across three samples, against one sample
each in the baselines. Honest framing: 3/3 here vs 2/2 archived clean is strongly suggestive of a
behaviour change in the b11458 → b11540 window, but it is not a matched-n A/B and the sampling is
`temperature 0.7`, so it is not proof.

I did **not** modify the grader. Calling this a PASS by stripping the prose myself would be
changing the test to fit the output, which is exactly what the suite forbids. The row says FAIL,
and the finding says why it is a formatting failure rather than a markup defect — a human should
decide whether the criterion needs a "strip trailing prose after the closing fence" clarification.

### 3. A3 went into a degenerate loop on a 404 and never recovered

A3 (research: Ottawa YOW snowfall total) made **341 requests**, of which **334 were tool calls and
326 mention HTTP 404**. Every one of them fetched the same URL:

```
https://dd.weather.gc.ca/climate/canada/historical/daily_csv/station_34709.csv
```

That URL is dead — I fetched it independently and got **HTTP 404** (196 bytes of HTML). The URL is
built from a plausible-looking but wrong station id and path; the baselines used the ECCC
`climate-daily` API for station `6105976` (`OTTAWA CDA`).

The important part is not the wrong URL — it is that the agent **could not stop**. The harness's own
`dsh-repeat-tool-breaker` fired correctly after 5 consecutive failures:

```
Error: REPEAT_TOOL_BLOCKED: web_fetch (consecutive failures). The call was stopped before executing.
Failing target(s):
- exact:web_fetch:{"url":"https://dd.weather.gc.ca/…/station_34709.csv"} — 5 consecutive failures (the request returned HTTP 404)
- net:dd.weather.gc.ca/…/station_34709.csv — 5 consecutive failures …
- host:dd.weather.gc.ca — 5 consecutive failures …
This target is not going to start working because the call is rephrased.
```

…and the model then re-issued the **identical blocked call ~325 more times**, ignoring an explicit
instruction that other calls are not blocked. I terminated the run at **06:28:17Z, 27 m 45 s in**
(its own 1-hour `timeout` would have fired at 07:00:32Z) because the outcome was already determined
and the card was needed for V1–V3. `a3_snowfall.md` in this archive is 376 bytes: the entrypoint
banner and nothing else. **No answer was produced.**

The v0.6.0 baseline passed A3 with 47 calls. Whether this is a b11540 behaviour change or one bad
sample at `temperature 0.7` is not something this run can settle — 1 sample each.

### 4. A2 is correct on the fields that matter, with two deviations worth recording

Grading is against **the machine that ran the container** (`.90` / `control-host`), per the skill:

| field | expected | this run | verdict |
|---|---|---|---|
| CPU / memory / kernel | container host's | `i5-7500T`, 14 GiB, `7.0.0-34-generic` | ✅ correct |
| OS / distro | the image's | Debian 12 (bookworm) | ✅ correct |
| in a container | stated | **not stated** (`/.dockerenv` never mentioned) | ⚠️ missing |
| disk | container filesystem view | host block devices `sda`/`nvme0n1` | ⚠️ host view, defensible for "宿主机" |
| GPU | *absent, stated as such* | Intel HD Graphics 630 (iGPU), "无独立 GPU" | ⚠️ see below |

The GPU line needs care in both directions. The rubric expects "absent"; the model instead reported
the host's real integrated Kaby Lake GPU (`8086:5912`, `i915`), gathered from `/proc/bus/pci` and
`/sys/class/drm` — **not an invented discrete GPU**, and it explicitly stated there is no discrete
GPU. That is honest and it matches the prompt, which asks about the **host machine**. But the
container has no `/dev/dri`, so "no GPU usable in this container" would have been the sharper
answer. Recorded as a deviation from the rubric's expected shape, not as a fabrication.

### 5. V3 echoed the decoy family; V1 missed only the skill name

**V3** (tire sidewall). I read the image myself to adjudicate. It clearly shows `255/70R18`,
`M+S` under the three-peak-mountain snowflake, and `118S` — and **no legible brand**. The model:

- ✅ read `255/70R18`
- ✅ read `M+S` and the 3PMSF snowflake
- ❌ read the load/speed index as **`T103`** (truth `118S`) — note this is the decoy `104T`'s shape
- ❌ asserted brand and model as **"BFGoodrich All-Terrain T/A KO2"**, inferring from a marker.
  The prompt's decoys include `All-Terran`, and the ground truth states the brand is unreadable and
  that saying so is correct. This is the failure the task exists to catch.

The v0.6.0 baseline got the size right and misread the load index as `113S` but did **not** invent a
brand. This run is worse on that axis.

**V1** (game screenshot). Also adjudicated against the image, and the model did better than it first
appears: the `AWAKE` / `BLOSSOM.` tabs, `20M 45°`, `EP: -1000` and `4M` that looked like
inventions **are all genuinely on screen**. It read 莉拉, LV 700, LV6, XR2 激活, 850 %,
Lv.5 防御力减少 8 s, 400 %, 防御力减少 75 % and 沉默 correctly. Its single miss is the skill's name
**`千律`**, which is printed next to 必杀技 in the popup title.

---

## A1 review coverage (observation — reported, never gating)

```
files touched / inventory : 13 / 25  (52 %)
read calls (file_path)    : 12
missed                    : .dockerignore, .gitignore, LICENSE, bridge_test.go,
                            fakeclient_test.go, go.mod, go.sum, infer_test.go,
                            store_test.go, uniqueid_test.go, web_handler_test.go,
                            yamlstore_test.go
notable                   : all 7 _test.go files skipped — the same gap as every prior run
                            (44 % / 44 % / 56 % in the three measured arms); a scope choice,
                            not a backend property, so not scored
```

Spot-checks of A1's findings against the clone: `yamlstore.go:103 sanitizeTopic` matches the claim
exactly (`strings.NewReplacer("/", "_", …)` with no `..`/`.` guard), and `mqtt.go:343 randSuffix()`
does use `time.Now().UnixNano()%100000`. No fabricated file or line was found.

---

## Verdict

**The suite is NOT green: 5 PASS, 3 FAIL (T2, A3, V3). Recommendation: DO NOT PROMOTE.**

What contradicts a promotion:

1. **T2 fails its structural criterion in 3/3 samples**, reproducibly and with the same failure
   mode, while both archived baselines passed cleanly. The SVG payload is valid; the response is
   not a bare SVG document. Under the canonical grader this is a fail.
2. **A3 fails outright** — 341 calls, ~325 of them re-issuing a call the harness had already
   blocked, and no answer at all. A research task that cannot stop is a usable-capability failure,
   not a slow run.
3. **V3 fails**: the load/speed index is wrong and the brand was asserted when the image does not
   support it, which is precisely the decoy trap the task is built around.

What argues the *backend* is healthy and the failures are largely behavioural:

- **Zero crashes, zero OOM, `RestartCount=0`, no leak onto the XTX**, across 2.59 M log lines.
- **No performance regression anywhere**: decode flat-to-better on every completed task.
- The largest model buffer is **unsplit**, so nothing here is a memory-splitting artefact.
- The Intel stack is byte-identical to the v0.6.0 baseline, so the only thing that moved is
  llama.cpp `b11458` → `b11540`.

So this is not a stability or throughput problem. It is an **output-shape and
instruction-following** problem on three of eight tasks, and it is the kind of thing that a
dev build should be blocked on until someone decides whether it is a real behaviour change or
sampling noise — which two of the three failures (T2, A3) cannot distinguish at n=1–3.

**What would change this decision:** a repeat run showing T2 and A3 reproduce the same way (or not)
at the same sampling; ideally an A/B against `b11458`, the subtree this build advanced from, so the
comparison is a matched pair rather than against the older v0.6.0 stable.

---

## Restoration — verified end-to-end, not just `/health`

Production `b70-sycl` was stopped with explicit user consent for the duration of the run
(~50 minutes of actual testing) and restored afterwards. `/health` returning ok was **not**
accepted as proof:

| # | Check | Result |
|---|---|---|
| 1 | Worker `/health` (`:18080`) | `{"status":"ok"}` |
| 2 | Worker actually infers | `content='ok'`, `finish_reason=stop` |
| 3 | **Through the SMG router** (`X-SMG-Routing-Key`) | real completion, **not** 503 `no_available_workers` |
| 4 | Router `/workers` | `:18090` healthy/ready · `:18080` healthy/ready |

**Step 3 initially passed for the wrong reason and step 4 caught it.** Immediately after
`docker start b70-sycl`, a routed request returned a real completion while `/workers` still showed
the B70 as `healthy=False status=failed` — the request had been served by the XTX. Left at that,
the platform would have looked healthy while silently keeping the B70 out of rotation. Polling
showed the breaker **self-healed after ~75 s** (06:37:38 failed → 06:38:53 ready), so no
`docker restart smg` was needed. Anyone checking only `/health` or only a routed request would have
missed this.

Production environment drift check: `b70-sycl` still carries the **correct**
`LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_K/_V` names (the 2026-10-05 fix), so draft KV is genuinely
`q8_0` rather than silently at the f16 default.

Final state: `b70-sycl`, `xtx-vulkan`, `smg` all running; `b70-sycl` and `xtx-vulkan` both
`RestartCount=0`, `OOMKilled=false`. The candidate `b70-dev-test-b11540` is left **stopped but not
removed** for post-mortem.
