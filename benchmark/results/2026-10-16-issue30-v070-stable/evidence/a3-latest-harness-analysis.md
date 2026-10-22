# A3 on the latest dsh-container (0.2.1-rc.2 / breaker 0.11.6)

## What changed between the two arms

| | arm 1 (successful rerun) | arm 2 (latest harness) |
|---|---|---|
| harness | `sha256:8ae9360ede03…` (dsh 0.2.0-rc.2) | `sha256:ae65d5e03225…` (dsh **0.2.1-rc.2**) |
| breaker | 0.11.4 | **0.11.6** |
| backend image | `sha256:b265f403…` (v0.7.0) | **identical** |
| golden config | identical | **identical** |
| prompt | identical (re-extracted from the pinned skill, sha256 `8af83da1…` verified) | **identical** |
| breaker config | tightened | **tightened (same)** |

Plugin set in the new image: `dsh-browser 0.2.2`, `dsh-command-context-trim 0.6.7`,
`dsh-llm-session-header 0.4.1`, `dsh-mobile 0.6.13`, `dsh-repeat-tool-breaker 0.11.6`,
`dsh-web-search-pro 0.1.16-alpha.1` (all advanced).

## Does the new breaker fix the loop on its own? **No.**

`dsh-repeat-tool-breaker` 0.11.6 ships **exactly the same gate** as 0.11.4:

```
window 16 | onLimit ask | warnAt 7 | summarizeAt 11
limits: exact 12, cmd 12, net 12, sink 12, host 16
```

The only code change in 0.11.6 is **sink attribution** (`sinkVerb` finds the writing command
in a chain instead of crediting the first word), plus new `normalize.js` rules for discard
targets and `-o` option verbs. `defaults.js`, `window.js` and `block-policy.js` are
byte-identical to 0.11.4.

Verified by **replaying the first run's timed-out session** (584 tool calls) through
0.11.6's own `fingerprints()` + window accounting:

```
SHIPPED defaults  -> peak identical-fingerprint count in any 16-call window : 9
                     (limit 12)  ->  FIRST WOULD-BLOCK : NONE — the gate never fires
TIGHTENED          -> peak 9, limit 6  ->  FIRST WOULD-BLOCK : call #10
```

So **"upgrade the harness and the loop is fixed" is false** — the tightened config is still
required. This is the third data point on the same root cause (issue #29: breaker 0.8.7 did
not fingerprint the call shape; issue #30 run 1: 0.11.4's limits were never reached;
issue #30 run 2: 0.11.6 ships the same limits).

Also note: dsh 0.2.1-rc.2 **no longer materializes the `llm-pi-ai` provider row** in the
generated profile patch (the patch now carries only the `web-search-deepseek` row), so the
route must be declared explicitly in the test home's profile patch. Boot fails with
`NO_ADAPTER: no adapter registered for provider "lc"` otherwise.

## Result of arm 2: **A3 did NOT produce a total** — but it did not time out

| | run 1 (0.11.4 harness) | arm 2 (0.11.6 harness) |
|---|---|---|
| tool calls | 586 (first run) / 81 (rerun) | **88** |
| max repeats of one call | 130 | **2** |
| breaker blocks | — | **5** (`host:api.weather.gc.ca 6/6`, `7/6`, …) |
| wall | 1 h 00 m (killed, no answer) | **~11 min, completed** |
| final answer | none | **a report that states no reliable total could be given** |

The breaker did its job: the loop was cut (max repeats 2, five blocks fired). The agent
**adapted** and completed inside 11 minutes instead of burning the hour.

**But it gave up instead of finding the data**, and the reason is a source-discovery
outcome, not a backend or harness fault:

- The agent correctly identified that the ECCC OGC API collection
  `climate-daily` returns **genuinely empty** `TOTAL_SNOW` / `MEAN_TEMPERATURE` for
  `STN_ID=4337` (`OTTAWA MACDONALD-CARTIER INT'L A`, `CLIMATE_IDENTIFIER=6106000`).
  Independently verified from the agent's own downloaded file
  (`yow_2025.csv`, 365 rows, HTTP 200): `TOTAL_SNOW` non-empty **0/365**,
  `MEAN_TEMPERATURE` also empty. The agent's diagnosis was correct.
- It then reached **`ottawa.weatherstats.ca`** — the source that worked in the successful
  rerun — but probed two endpoints that do not carry the data:
  `/metrics/snow.html` (HTTP 200) and `/data/snow-daily.json` (HTTP 200, 993 bytes),
  and never tried `download.html?formdata=ok&type=daily&limit=50000`.
- It finally summarised the state honestly, including that the ECCC row is empty and
  listing alternative sources.

**The task was still answerable when the agent stopped.** Re-fetching the same endpoint
afterwards returned HTTP 200 and the identical numbers:

```
rows: 6000
days=354  TOTAL=258.6 cm  snowdays=75  max=21.0 on 2026-01-15
monthly: 2025-11 32.5 | 2025-12 54.6 | 2026-01 81.6 | 2026-02 48.3 |
          2026-03 41.0 | 2026-04 0.6 | 2026-05..2026-10 0.0
```

Same total, same 75 snow days, same max day, same twelve monthly values as the successful
rerun and as the independent re-check of that run. The ECCC/weatherstats data itself is
stable and was not the problem.

**Conclusion: A3's outcome is not reproducible across harness versions, because it depends
on which endpoints the agent happens to probe — an external-data-discovery variable, not a
backend property.** The v0.7.0 backend served both arms identically.

## Arm 2 metrics (same image, same golden config)

| task | prompt_tok (largest) | prefill tok/s | TTFT s | completion_tok | decode tok/s | accept % (K=3) | requests |
|---|---|---|---|---|---|---|---|
| A3 (latest harness) | 12173 | 571.01 | 21.318 | 12734 | 33.83 | **78.7** (8897/11298) | 90 |

Stability: 392 003 log lines, zero SIGSEGV / OOM / allocation-failure / device-loss
signatures; `SYCL0 model buffer size = 17402.38 MiB` unsplit.
