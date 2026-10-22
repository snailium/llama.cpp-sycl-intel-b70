# A3 rerun — root cause of the first run's timeout, and the fix

## Symptom (first run, issue #30)

A3 was killed by the 1 h cap (`rc=124`) with **no final answer**: 586 tool calls, zero
assistant text blocks. The session ended inside a repetitive probe of
`api.weather.gc.ca` / `climatedata.ca` endpoints.

## Measured root cause — the repeat-tool-breaker gate never fired

The harness ships `dsh-repeat-tool-breaker` **0.11.4** (the same plugin whose 0.8.7 → 0.11.3
bump fixed the identical A3 timeout in issue #29). So this was *not* the old coverage hole.

The loop in the first run was:

| repeated call | occurrences | max occurrences in any 16-call window |
|---|---|---|
| one identical `bash` command (parse `climatedata.ca-wp-json.json`) | **125** | **9** |
| one identical `web_fetch_file` URL (`climatedata.ca/wp-json/cdc/v2/location_search…`) | **130** | **8** |

The plugin's shipped defaults are `window: 16` and `limits.exact/cmd/net/sink: 12`,
`limits.host: 16`. A call is denied when one of its fingerprints has **already appeared
`limit` times inside the window** — so the gate needed **12** identical fingerprints in a
16-call window, and the observed peak was **9**. The gate was never reached, so the loop ran
for the full hour.

Secondary factor: `onLimit: ask` cannot work unattended. The plugin is fail-closed — an
approval whose outcome is `unavailable` is a denial — and the session shows exactly that
(`approval/decided {"outcome": "unavailable"}`), 3 times, all on the *failure* track
(`host:dd.weather.gc.ca` 404s). Worse, `onPre` skips asking once any blocking measure was
already refused in that turn, so later asks can be suppressed entirely.

## The fix (harness-side only — the image, the golden config and the prompt are unchanged)

In the rerun's **profile** `cordis.patch.yml`, the `repeat-tool-breaker` row was reconfigured:

```yaml
- id: repeat-tool-breaker
  name: 'dsh-repeat-tool-breaker'
  config:
    window: 16
    onLimit: deny          # was: ask -- no approval channel exists in headless mode
    warnAt: 3
    summarizeAt: 5
    limits:
      exact: 5             # was 12
      cmd: 5               # was 12
      net: 5               # was 12
      sink: 5              # was 12
      host: 6              # was 16
```

Validated against the plugin's own code (extracted from the harness image) before the run:

- `mergeDefaults` + `validateCfg` accept the config; effective limits read back as
  `exact/cmd/net/sink 5, host 6, onLimit deny`.
- The loop command's fingerprints are `exact:bash:{…}` and `cmd:cd:…` — **two capped
  measures**, both blocking at the 5th occurrence, comfortably below the observed peak of 9.

## Result

| | first run | rerun |
|---|---|---|
| tool calls | 586 | **81** |
| max repeats of one call | 130 | **5** (the cap) |
| wall | 1 h 00 m (killed) | **~35 m, completed** |
| final answer | none | **258.6 cm, with source, method and monthly breakdown** |
| `REPEAT_TOOL_BLOCKED` results | 0 on the occurrence track | breaker cut the loop as designed |

The agent adapted after each block instead of re-issuing the blocked call, then found a
source that worked: `ottawa.weatherstats.ca/download.html?formdata=ok&type=daily&limit=50000`
(an ECCC-sourced mirror of daily station observations), downloaded the full 8.9 MB CSV
(50 000 rows, columns include `date`, `snow`, `snow_on_ground`, `precipitation`, `rain`),
filtered 2025-11-01 … 2026-12-31, and summed the `snow` column.

## Independent re-check of the number

Recomputed from the agent's own downloaded CSV
(`workspace/fetched/yow_daily_full.csv`), **not** from the agent's arithmetic:

```
days with data : 353
TOTAL SNOW     : 258.6 cm
snow days      : 75
max single day : 21.0 cm on 2026-01-15
monthly        : 2025-11 32.5 | 2025-12 54.6 | 2026-01 81.6 | 2026-02 48.3 |
                 2026-03 41.0 | 2026-04 0.6 | 2026-05..2026-10 0.0
```

Every figure the agent reported is reproduced exactly. The unit is **cm of snowfall**
(`snow`, not `snow_on_ground`), and the 73-day gap is the 2026-10-20 → 2026-12-31 tail where
observations do not yet exist — the agent stated this explicitly rather than silently
treating it as zero-and-complete.

## Rerun metrics (same image, same golden config)

| task | prompt_tok (largest) | prefill tok/s | TTFT s | completion_tok | decode tok/s | accept % (K=3) |
|---|---|---|---|---|---|---|
| A3 (rerun) | 12483 | 598.49 | 20.857 | 11414 | 37.31 | **79.6** (8000/10053) |

Stability: 301 850 log lines, zero SIGSEGV / OOM / allocation-failure / device-loss
signatures; `RestartCount=0`; `SYCL0 model buffer size = 17402.38 MiB` unsplit.
