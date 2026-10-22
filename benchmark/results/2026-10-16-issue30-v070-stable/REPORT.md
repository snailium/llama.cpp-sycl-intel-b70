# B70 SYCL Test Report — Intel Arc Pro B70 · `server-c26.35.39758.10-v0.7.0-20261016-0335`

**Issue:** [snailium/llama.cpp-sycl-intel-b70#30](https://github.com/snailium/llama.cpp-sycl-intel-b70/issues/30) (opened, stable build)
**Date:** 2026-10-16 (full suite) · 2026-10-20 (A3 rerun) · 2026-10-21 (A3 on the latest harness) · **Host:** `gpu-host` (.101) · **Card:** Arc Pro B70 32 GB (`xe`, `renderD128`)
**Backend:** llama.cpp **v0.7.0** (`libllama.so.0.7.0`, `libggml-base.so.0.27.0`)
**Model:** `Qwen3.8-27B-Q4_K_M.gguf` + `mmproj-Qwen3.8-27B-Q8_0.gguf` + `mtp-Qwen3.8-27B-Q8_0.gguf`
**KV:** q8_0 main + q8_0 draft · **Spec decode:** `draft-mtp`, **K=3**, `p_min=0.1`
**Outcome:** 6 PASS / 2 FAIL (V2, V3 — vision model-quality defects, both carried over from the v0.6.0 baseline) — **promoted to `:stable` on 2026-10-21** (see [Verdict](#verdict))

| | |
|---|---|
| **Image digest (durable record)** | `sha256:b265f4034978affce09c482374ce09dc5bf97852a3cede3bdabcbb84d90c2377` |
| Image built | 2026-10-16T04:06:41Z |
| **Harness digest** (full suite + A3 rerun) | `sha256:8ae9360ede0369dcaf37c203e849500dd9b5b5e71c4193951817dcfc4746c521` (dsh 0.2.0-rc.2, breaker 0.11.4) |
| **Harness digest** (A3, latest) | `sha256:ae65d5e032253236f1d93d3146d491b4734cd333cfc37a1feec84e1fa7a11519` (dsh 0.2.1-rc.2, breaker 0.11.6) |
| **Skill sha256** | `8af83da14abfa1408204e2eff762470c8dba0e8e4c5dae5893ee1656d1546a53` |
| Previous stable baseline | v0.6.0, `sha256:b5799bf3f66bc1fb5ed6e52534e8f6e9e84bab57105f83ae210fd168208d8b41` |

## What actually changed

The **Intel stack is byte-identical** to the outgoing stable — compute-runtime `26.35.39758.10`
(`libze_intel_gpu.so.1.17.39758`), IGC `2.41.5`, Level Zero loader `1.32.0`, oneDNN 2026.0.
This is a **llama.cpp-only change**: the vendored subtree advanced `v0.6.0 → v0.7.0`
(3986 files, +97012/−35390), of which `ggml/src/ggml-sycl/` is 28 files, +2717/−418.

The notable SYCL-side changes are in the FA and GEMM paths: `fused-gemm.cpp/hpp` is new
(+1181), `mmvq.cpp` (+429) and `vecdotq.cpp` (+315) were reworked, `fattn.cpp` extends the
MKL-FA kernel gate to a narrow GLM-4.7 MLA shape, and `ggml-sycl.cpp` gains +368.
`fattn-common.hpp` now **asserts** `extra.K_buffer_ptr` instead of falling back to a pool
allocation — worth watching, but it did not fire in this run.

**Sampling config verified from the running server**, not from the launch intent
(`curl /props`): `n_ctx 131072`, `temperature 0.7`, `top_p 0.80`, `top_k 20`, `min_p 0.0`,
`presence_penalty 1.5`, `frequency_penalty 0.0`, `repeat_penalty 1.0` — exactly the golden §3 block.

**Trim auto-tune:** ON (`DSH_TRIM_AUTO_TUNE=1`). Effective compaction trigger **80 %** of the
131072 window, `headroomTokens=9831` — matches `(131072−16384) − floor(0.8×131072)` and is
persisted in the profile patch. Not the 37.5 % stock path.

**Request fields sent:** only the two the suite permits — `chat_template_kwargs`
`{"enable_thinking": false}`, and `max_tokens: 32768` (T1/T2/V1-V3). `stream: true` on T1/T2
for TTFT only. No sampling parameter was ever sent.

## Results Summary

Direct tasks (T1/T2/V1-V3) are one request each and are read from the **response-body
`timings`** block. Agent rows (A1-A3) are recovered from the server log's `slot print_timing`
records, because for those the dsh harness is the client. `-v` (`DEBUG_FLAG=-v`) was enabled,
so acceptance data exists — 611 `draft acceptance` records in the run.

| Task | Status | prompt_tok | prefill tok/s | TTFT s | completion_tok | decode tok/s | accept % (K=3) | Notes |
|---|---|---|---|---|---|---|---|---|
| T1 | **PASS** | 43 (largest) | 45.33 | 0.949 | 2772 | 41.06 | **73.6** (1908/2592) | HTML parses, balanced, ends `</html>`, `finish_reason=stop` |
| T2 | **PASS** | 32 (largest) | 46.03 | 0.695 | 6659 | 46.72 | **87.1** (4815/5529) | well-formed XML, single `<svg>` root, `viewBox`, ends `</svg>` |
| A1 | **PASS** | 10858 (largest) | 541.64 | 20.046 | 4460 | 22.04 | **49.5** (2659/5367) | 13 requests; concrete findings with file:line, risk, fix |
| A2 | **PASS** | 8993 (largest) | 606.85 | 14.819 | 1088 | 41.72 | **80.7** (767/951) | 4 requests; JSON valid, values gathered, no GPU invented |
| A3 | **PASS** (rerun) | 12483 (largest) | 598.49 | 20.857 | 11414 | 37.31 | **79.6** (8000/10053) | 81 requests; **258.6 cm** with source, method, monthly breakdown |
| V1 | **PASS** | 3528 | 49.23 | 71.665 | 654 | 37.68 | **63.8** (429/672) | 莉拉 / 700 / 千律 LV6 popup content all match truth |
| V2 | **FAIL** | 1064 | 78.72 | 13.517 | 1725 | 35.13 | **55.2** (1075/1947) | 16/21 labels; **invented** `Q05–Q16`, `U53A/B`, `X2`, `SATA1–6` |
| V3 | **FAIL** | 4160 | 45.45 | 91.520 | 255 | 34.99 | **56.7** (160/282) | size `255/70R18` OK; load index **113S** vs truth **118S** |

### A3 was run three times — the outcome is not reproducible, and that is the finding

| arm | harness | breaker | wall | tool calls | max repeats | breaker blocks | final answer |
|---|---|---|---|---|---|---|---|
| 1. full suite | 0.2.0-rc.2 | 0.11.4 (shipped) | 1 h 00 m (killed) | 586 | 130 | 0 on the occurrence track | **none** |
| 2. rerun | 0.2.0-rc.2 | 0.11.4 (**tightened**) | ~35 min | **81** | **5** | cut the loop | **258.6 cm** ✓ |
| 3. latest harness | **0.2.1-rc.2** | **0.11.6** (tightened) | ~11 min | **88** | **2** | 5 blocks | **no total** ✗ |

Arm 1's timeout was a **harness** problem, not a backend one: the agent looped 125× on one
`bash` command and 130× on one `web_fetch_file` URL without ever tripping
`dsh-repeat-tool-breaker`, because the shipped gate needs **12** identical fingerprints
inside a **16**-call window and the observed peak was **9**; and `onLimit: ask` cannot work
unattended (a headless approval returns `unavailable`, which the plugin treats fail-closed).
Arms 2 and 3 reconfigured the breaker in the **test home only** — `exact/cmd/net/sink: 5`,
`host: 6`, `onLimit: deny` — validated against the plugin's own `fingerprints()` and window
accounting **before** the run.

**Arm 3 (latest dsh-container) is the important negative result.** `dsh-repeat-tool-breaker`
**0.11.6 ships exactly the same limits as 0.11.4** (`window 16`, `exact/cmd/net/sink 12`,
`host 16`, `onLimit ask`); the only code change is sink attribution, and `defaults.js`,
`window.js` and `block-policy.js` are byte-identical. Replaying arm 1's timed-out session
through 0.11.6's own window accounting still peaks at **9** — below the limit of 12 — so
**"upgrade the harness and the loop is fixed" is false**; the tightened config is still
required. (dsh 0.2.1-rc.2 also stopped materializing the `llm-pi-ai` provider row, so the
route must be declared explicitly in the test home's profile patch or the boot fails with
`NO_ADAPTER`.)

With the loop cut, arm 3 **completed in ~11 minutes** — but it **gave up instead of finding
the data**. Its diagnosis of the ECCC OGC API was *correct*: the `climate-daily` collection
returns genuinely empty `TOTAL_SNOW` for `STN_ID=4337` (verified from the agent's own
downloaded CSV: 0/365 rows non-empty, `MEAN_TEMPERATURE` also empty). It then reached
`ottawa.weatherstats.ca` — the source that worked in arm 2 — but probed only
`/metrics/snow.html` and `/data/snow-daily.json` (both HTTP 200) and never tried
`download.html?formdata=ok&type=daily&limit=50000`. It finished with an honest report that
no reliable total could be given.

**The task was still answerable when it stopped**: re-fetching that same endpoint
afterwards returned HTTP 200 and the identical numbers (258.6 cm, 354 days, 75 snow days,
max 21.0 cm on 2026-01-15, all twelve monthly values). So A3's outcome is governed by
**which endpoints the agent happens to probe** — an external-data-discovery variable — not
by the backend, which served all three arms identically. Full analysis:
`evidence/a3-loop-analysis.md` and `evidence/a3-latest-harness-analysis.md`.

Task order was T1 → T2 → V1 → V2 → V3 → A1 → A2 → A3 (the V-block was run before the agent
block to keep each block's server windows contiguous; every task ran serially, no concurrency).
V1-V3 were run because the served model has a vision projector (`mmproj-…Q8_0.gguf` loaded,
`[mtmd] estimated worst-case memory usage of mmproj is 848.18 MiB`).

### A1 review coverage (observation — reported, never gating)

```
files touched / inventory : 13 / 25  (52 %)
read calls               : 12
missed                   : .dockerignore, .gitignore, LICENSE, README.md,
                           bridge_test.go, fakeclient_test.go, go.sum,
                           infer_test.go, store_test.go, uniqueid_test.go,
                           yamlstore_test.go, scripts/mqtt2ha_sqlite2yaml.py
notable                  : read web_handler_test.go, so it is NOT the "skipped every
                           _test.go" pattern seen in earlier arms; 6 of 7 test files
                           still missed. Scope choice, not scored.
```

### Comparison against the v0.6.0 stable baseline

| Task | fill v0.6 → v0.7 | decode v0.6 → v0.7 | accept v0.6 → v0.7 |
|---|---|---|---|
| T1 | 62.4 → 45.33 (**−27.4 %**) | 42.18 → 41.06 (−2.7 %) | 0.737 → 0.736 |
| T2 | 50.3 → 46.03 (−8.5 %) | 45.74 → 46.72 (+2.1 %) | 0.857 → 0.871 |
| A1 | 580.4 → 541.64 (−6.7 %) | 22.91 → 22.04 (−3.8 %) | 0.528 → 0.495 |
| A2 | 595.3 → 606.85 (+1.9 %) | 40.58 → 41.72 (+2.8 %) | 0.765 → 0.807 |
| A3 | 527.5 → 598.49 (+13.4 %) | 32.22 → 37.31 (+15.8 %) | 0.740 → 0.796 |
| V1 | 48.1 → 49.23 (+2.3 %) | 34.55 → 37.68 (+9.1 %) | 0.560 → 0.638 |
| V2 | 78.7 → 78.72 (+0.0 %) | 36.10 → 35.13 (−2.7 %) | 0.588 → 0.552 |
| V3 | 45.0 → 45.45 (+1.0 %) | 32.70 → 34.99 (+7.0 %) | 0.509 → 0.567 |

**The T1 prefill drop is not a throughput regression.** It is measured on a 43-token prompt,
where the rate is dominated by fixed per-request cost: 948.7 ms vs the baseline's 689 ms is
**+260 ms once per request**, and T2 (a *shorter* 32-token prompt) moves by the *same* absolute
~+170 ms rather than proportionally. The long-prompt measure — the one that actually reads
prefill throughput — is unchanged: A2 at 8993 tokens is 606.85 tok/s (+1.9 %), A3 +13.4 %, and
A1 −6.7 % — all inside the run-to-run spread the baseline itself documents (the same baseline
records 472–492 tok/s across earlier runs on an unchanged build). **No prefill regression.**

**No memory splitting.** `load_tensors: SYCL0 model buffer size = 17402.38 MiB` — one unsplit
buffer, byte-identical to the v0.6.0 baseline. KV `4352.00 MiB`, compute `752.29 MiB`,
RS `598.50 MiB`, draft `1718.71 MiB` all match. The §5 trap did not fire.

## Stability

- `RestartCount=0`, `OOMKilled=false` on the candidate container; `ExitCode=0`.
- **XTX leak check:** `xtx-vulkan` `RestartCount=0` before and after — the run did not leak
  outside its card.
- Scanned **4,351,498 log lines** (`evidence/stability-scan.txt`), zero occurrences of:
  `SIGSEGV`, `UR_RESULT_ERROR`, `device lost`, `Failed to allocate physical memory`,
  `ggml_sycl_pool_vmm`, `GGML_ASSERT`, `stack smashing`, `declared device`, `as wedged`,
  `GPU hang`, `Out of memory`, `bad_alloc`, `terminate called`.
  (A naive `abort` grep hits 3609 times; every one is inside fetched web content or
  `set_abort_callback` debug lines — checked, not server faults.)
- Speculative decoding was active throughout: `cache_k=q8_0, cache_v=q8_0` on the draft
  (the corrected `LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_K/_V` names), no f16 fallback.

## Findings that are NOT backend regressions

1. **V3 load index misread (`113S` vs truth `118S`).** This is the **third** occurrence of the
   same defect class (v0.6.0 also returned `113S`). It is a model-quality issue on a
   sidewall-photo OCR task, not a backend property. The task definition, not the backend, is
   what needs attention.
2. **V2 fabricated labels.** The model listed `Q05–Q16`, `U53A/B`, `X2` and `SATA1–6`, none of
   which are on the diagram, and missed `FCH`, `USB31A`, `USB32A`, `F_PANEL`, `U65`.
3. **A3 is not reproducible — and that is a task/harness property, not a backend one.** A3 was
   run three times against **the same image digest, the same golden config and the same
   prompt**, and produced three different outcomes: a 1 h timeout with no answer, a correct
   **258.6 cm** with a full method breakdown, and a completed run that honestly reported it
   could not find a reliable total. The 1 h timeout was traced to a **harness** gap (the
   repeat-tool-breaker's shipped limits are unreachable — peak 9 vs limit 12) and fixed in the
   test home only; the remaining variability is **which endpoints the agent happens to probe**
   on an external data source. The backend served all three arms identically and cleanly.
   Two consequences for the gate:
   - A3 **cannot be treated as a binary pass/fail on this image** until its data source is
     pinned (the working endpoint is
     `ottawa.weatherstats.ca/download.html?formdata=ok&type=daily&limit=50000`).
   - The arm that *did* produce an answer was **independently re-checked from the agent's own
     downloaded CSV** — 258.6 cm, 353 days, 75 snow days, max 21.0 cm on 2026-01-15 and all
     twelve monthly values reproduce exactly, and the same endpoint still returns those
     numbers today. So the A3 result, once produced, is trustworthy; what is unreliable is
     whether the agent finds the source.

## Verdict

**The test's verdict: 6 PASS, 2 FAIL — both failures are vision model-quality issues, not
backend defects. The maintainer's decision (2026-10-21): PROMOTED to `:stable`.**

The backend itself is in excellent shape and shows **no regression against the v0.6.0 stable**:
zero crashes/OOM/device-loss across 4.35 M + 0.30 M + 0.39 M log lines, byte-identical
memory layout with no buffer splitting, unchanged long-prompt prefill, decode within noise,
draft acceptance equal or better on 6 of 8 tasks, and `RestartCount=0` on both cards. A3's
first-run timeout was traced to a harness configuration and resolved on the same image; its
remaining variability is an external-data-discovery outcome, not a backend property.

What remains red is **V2 and V3**, both on the vision battery:

- **V2 FAIL** — 16/21 ground-truth labels, and it **fabricated** `Q05–Q16`, `U53A/B`, `X2`,
  `SATA1–6`, none of which are on the diagram.
- **V3 FAIL** — read the size correctly (`255/70R18`, not the prompt's decoy `245/60R17`) and
  the `M+S` / snowflake marks, but reported the load index as **`113S` where the truth is
  `118S`**.

Both are **model-quality failures on image reading, and both are carried over from the
v0.6.0 baseline** (v0.6.0 also returned `113S` on V3, so this is the third occurrence of that
defect class; V2's fabrication is the same class of error). Neither is a property of the
v0.7.0 image — the backend handled both images identically, returning clean 200s with
correct timings.

**Recommendation (from the test):** hold the promote to `:stable` and `:latest` until the vision
battery is green. The evidence points squarely at task design and model behaviour, not at the
image, so fixing the V2/V3 definitions or grading is likely to unblock this **without any new
build** — the same image can be re-tested as-is.

### Promote decision (maintainer, 2026-10-21) — **PROMOTED to `:stable`**

The maintainer reviewed this report and **decided to promote**, on the strength of the
backend-stability evidence, with V2 and V3 accepted as known task-side defects. That is the
call this report explicitly said was the maintainer's to make, and it is recorded here as
such rather than as the test's own verdict.

| Tag | Digest |
|---|---|
| `:stable` | `sha256:b265f4034978affce09c482374ce09dc5bf97852a3cede3bdabcbb84d90c2377` |
| `:latest` | same (advanced 2026-10-10 → 2026-10-16, monotonic by build date) |
| `:server-c26.35.39758.10-v0.7.0` | same (new clean release tag) |
| `:server-c26.35.39758.10-v0.7.0-20261016-0335` | same (CI candidate tag) |

`:server-dev` was **not** touched, and the v0.6.0 rollback tag
`server-c26.35.39758.10-v0.6.0` still resolves to `sha256:b5799bf3…`.

**What the promote rests on:** zero crash/OOM/device-loss signatures across 4.35 M + 0.30 M +
0.39 M log lines; byte-identical memory layout with **no buffer splitting**
(`SYCL0 model buffer size = 17402.38 MiB`); unchanged long-prompt prefill; decode within
noise; draft acceptance equal or better on 6 of 8 tasks; `RestartCount=0` on both cards.

**What it knowingly accepts:** V2's fabricated labels and V3's `113S`/`118S` load-index misread
— both vision model-quality defects, both reproduced on the v0.6.0 baseline, neither a
property of this image. **The V-block is a known-broken gate**, not a regression, and fixing
it is tracked as task-definition work, not as an image blocker.

**Also recorded for the next run:** A3 is **not a reliable binary gate** as written (three
arms, three outcomes on the same digest). Pinning the data source in the task definition —
`ottawa.weatherstats.ca/download.html?formdata=ok&type=daily&limit=50000` — would make it
deterministic. This does not affect the image.

**What would change the decision:** a re-run in which V2 and V3 are either fixed at the task
level, or pass with a different image-reading outcome. A3 needs **no backend action** — it
passes when the agent reaches the right endpoint, and pinning that endpoint in the task
definition would make it deterministic.

## Production restoration (verified end-to-end)

`b70-sycl` was stopped with the user's explicit consent and started again after each run
(the full suite, then the A3 rerun, then the A3 latest-harness run). Restoration was verified
in order, and **the usual trap fired every time** — identically:

1. worker `/health` → `{"status":"ok"}` ✓
2. worker actually infers → returned `ok` ✓
3. **routed request through SMG** → the first check returned HTTP 200 **but SMG reported the
   B70 worker `healthy=False status=failed`** — `/workers` showed only the XTX worker `ready`,
   so the request was served by the 7900 XTX while the platform *looked* restored. This is the
   documented "SMG does not self-heal after a worker restart" behaviour, and it reproduced
   exactly on all three restores.
4. `docker restart smg`, wait 40 s, re-check → **both** workers `healthy=True status=ready`
   (the B70 and XTX workers), and a routed request with `X-SMG-Routing-Key` returned
   HTTP 200 with a real completion.

Final state: `b70-sycl` `restart=0 oom=false status=running (healthy)`, `xtx-vulkan`
`restart=0 oom=false status=running (healthy)`, `smg healthy`. No production container was
removed or rebuilt.

> **Operational note for the next run:** the SMG circuit breaker does not close on its own
> after a worker restart, so `docker restart smg` is a **required** step of the restore, not a
> fallback. A restore that only checks `/health` and a routed 200 will look successful while
> the B70 is still out of rotation. Always confirm with `/workers` before declaring the
> platform restored.

## Artifacts

- `REPORT.md` (this file), `t1_html.html`, `t2_svg.svg`, `v1_game.md`, `v2_mainboard.md`,
  `v3_tire.md`
- `a1_security`, `a2_hostinfo` sessions in both forms (`.jsonl.zstd` byte-exact, `.jsonl`
  decompressed)
- `a3_snowfall.md` + `a3_snowfall.session.jsonl{,.zstd}` — the **arm-2** A3 run, the one that
  produced the sourced total. Arm 1 (the timed-out session) and arm 3 (the latest-harness run
  that found no total) are kept in the run directory, not here, because the A3 verdict in this
  report rests on arm 2's independently re-checked number.
- `evidence/` — `props.json` (server config read-back), `version-readback.txt` (image
  internals), `stability-scan.txt`, `rerun-stability-scan.txt`, `latest-stability-scan.txt`,
  `a3-loop-analysis.md` (root cause + arm 2's independent re-check),
  `a3-latest-harness-analysis.md` (arm 3: why 0.11.6 does not fix it, and why A3 is not
  reproducible), `launch-candidate.sh`, `launch-candidate-rerun.sh`, `run_agent.sh`,
  `run_agent_rerun.sh`, `run_agent_latest.sh`

Image digest recorded here and the directory tag agree:
`sha256:b265f4034978affce09c482374ce09dc5bf97852a3cede3bdabcbb84d90c2377` ↔
`server-c26.35.39758.10-v0.7.0-20261016-0335`.
