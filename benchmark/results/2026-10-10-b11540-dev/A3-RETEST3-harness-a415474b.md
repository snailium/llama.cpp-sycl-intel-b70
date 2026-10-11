# A3 — third attempt, harness `a415474b` (repeat-tool-breaker 0.8.7 → 0.11.3)

**Outcome: A3 PASSES.** The loop is fixed, and the fix is attributable to a single changed plugin.

## The three attempts, side by side

All three ran the **same backend container** (`b70-dev-test-b11540` @ `sha256:8bfbe375…`), the same
golden config, and the same prompt (`a3_snowfall`, sha256 `464f1f898c978b56`, read from the pinned
skill file each time). The harness is the only variable.

| # | harness digest | repeat-tool-breaker | outcome | wall | tool calls | max repeats of one call | trailing run | answer |
|---|---|---|---|---|---|---|---|---|
| 1 | `c88327dd` | 0.8.7 | **no answer**, killed at 27 m 45 s | 27 m | 334 | ~325 | ~325 | none (376 B) |
| 2 | `3c525ab3` | 0.8.7 | **no answer**, killed at 48 min | 48 m | 280 | 102 | **102** | none (1,881 B) |
| 3 | **`a415474b`** | **0.11.3** | **COMPLETED** (`rc=0`) | **8 m 0 s** | **74** | **5** | **0** | **4,660 B** |

Run 3 made 72 requests in the measured window and produced a complete answer. `REPEAT_TOOL_BLOCKED`
fired **8 times** (call indices 11, 12, 34, 53, 57, 59, 63, 71) and the agent **adapted after each
one** instead of re-issuing the blocked call — the exact behaviour that was absent in runs 1 and 2.

## Why the fix lands: verified against the plugin's own code

The two releases differ in **one thing only**. Inventory of `/plugs/` across the two images:

| plugin | `3c525ab3` | `a415474b` |
|---|---|---|
| dsh-browser | 0.2.0-rc.1 | 0.2.0-rc.1 |
| dsh-command-context-trim | 0.6.6 | 0.6.6 |
| dsh-llm-session-header | 0.4.0 | 0.4.0 |
| dsh-mobile | 0.5.3 | 0.5.3 |
| **dsh-repeat-tool-breaker** | **0.8.7** (112,748 B) | **0.11.3** (129,157 B) |
| dsh-web-search-pro | 0.1.16-alpha.1 | 0.1.16-alpha.1 |

dsh itself is `0.2.0-rc.2` in both. I extracted 0.11.3 and ran its fingerprint extractor
(`lib/fingerprints.js`) directly against the exact call that run 2 looped on 102 times:

```
bash heredoc loop  <-- the call run 2 repeated 102x
   cap=  12  exact:bash:{"command":"python3 - <<'EOF'\nimport re\nsrc = open('/tmp/dsh-spill-…
   cap=none  verb:python3
   cap=  12  cmd:python3:python3 - <<EOF import re src = open(/tmp/dsh-spill-…
```

Under 0.8.7 that call produced no capped fingerprint, which is why it never blocked. Under 0.11.3 it
produces `exact:` and `cmd:`, both capped at 12. Driving the new logic over 102 identical calls:
**first block at call 12, 91 of 102 blocked.** The simulation predicted run 3's behaviour, and run 3
confirmed it (max repeats 5, trailing run 0).

This is the correct diagnosis of the run-2 finding: the coverage hole was real, it was in that
plugin, and 0.11.3 closes it.

## The answer

> **145.7 cm** total for 2025-11-01 → 2026-10-11, from **Open-Meteo Historical Weather API**
> (ECMWF IFS reanalysis), grid point 45.31 °N / −75.66 °W, hourly `snowfall` summed over 8,280 hours;
> 97 snow days; monthly breakdown given (Nov 21.8, Dec 31.1, Jan 39.1, Feb 27.0, Mar 22.5, Apr 4.0,
> May 0.3 cm).

**Independently re-checked.** I fetched the same API endpoint myself and recomputed:

| | A3's answer | my recomputation |
|---|---|---|
| grid point | 45.31, −75.66, elev 119 m | 45.307556, −75.65625, elev **112.0 m** |
| hours | 8,280 | 8,280 |
| total 2025-11-01 → 2026-10-11 | 145.7 cm | **145.7 cm** ✅ |
| Nov 2025 | 21.8 cm | **21.8 cm** ✅ |
| Dec 2025 | 31.1 cm | **31.1 cm** ✅ |
| Jan 2026 | 39.1 cm | **39.1 cm** ✅ |
| Feb 2026 | 27.0 cm | **27.0 cm** ✅ |
| Mar 2026 | 22.5 cm | **22.5 cm** ✅ |
| Apr 2026 | 4.0 cm | **4.0 cm** ✅ |
| May 2026 | 0.3 cm | **0.3 cm** ✅ |
| Nov+Dec 2025 | 52.9 cm | **52.9 cm** ✅ |

Every figure reproduces exactly. The elevation is reported as 119 m where the API returns 112 m — a
trivial bookkeeping slip that does not affect any token of the answer.

**The task's hard part was handled correctly and honestly.** The requested range ends 2026-12-31, but
"today" is 2026-10-11, so roughly three months of the request are **in the future**. The agent:

- reported the API's own error verbatim (`end_date is out of allowed range from 1940-01-01 to 2026-10-11`),
- stated plainly that the tail cannot exist rather than inventing values for it,
- gave the total for the range that *does* exist and split out the sub-periods,
- disclosed that it **could not reach Environment Canada** (`dd.weather.gc.ca` 404s,
  `climate.weather.gc.ca` unreachable, shell HTTP blocked by the sandbox) and named the substitute
  source instead of implying it had used the official one,
- flagged that reanalysis is a modelled estimate (±20–30 % vs a station observation) and pointed at
  the authoritative station for anyone needing the exact figure.

That is the required shape: a total with its unit, a named and re-checkable source, the underlying
data, and the limitation stated rather than hidden.

## Metrics (run 3, task window only)

| metric | value |
|---|---|
| calls in window | 72 |
| largest prompt | 9,016 tok |
| prefill | 386.49 tok/s |
| TTFT (first call prompt-eval) | 1.52 s |
| completion | 8,982 tok |
| decode | 34.51 tok/s |
| draft acceptance | **80.7 %** (6,321 / 7,833), K = 3 |

Runs 1 and 2 have no comparable row — their aggregates describe hundreds of repetitions of one
failing call, not a workload.

## Effect on the gate

A3 moves from **FAIL** to **PASS**. The main run's suite verdict therefore becomes **6 PASS / 2 FAIL
(T2, V3)**; that verdict still stands as written, because T2 and V3 were not retested and A3's
original failure was real at the time it was recorded — it was a harness defect surfaced by this
test, not a property of the b11540 backend.

Worth stating explicitly, because it inverts part of the earlier write-up: run 2's conclusion that
*"this is not the model ignoring the breaker; the breaker only covers failing network fetches"* was
correct and is now confirmed by the fix. Runs 1 and 2 said more about the **harness's** loop
protection than about llama.cpp. What remains genuinely open about the backend is **T2** (prose after
the SVG, 3/3 samples) and **V3** (the `118S` misread and the invented tyre brand).

## Restoration

Card held ~9 minutes. Server log dumped before teardown (4,712,213 lines). Production restored and
verified end-to-end — and **step 4 caught it a third time**: `/health` was `ok` and the worker
inferred while SMG reported `18080=False/not_ready`. The breaker cleared after ~100 s
(20:54:54 not_ready → 20:56:34 ready). Final: all three containers up, `RestartCount=0`,
`OOMKilled=false`. Candidate left stopped, not removed.
