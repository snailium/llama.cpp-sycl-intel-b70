# A3 retest on the updated harness — reproducibility check

**Question this run answers:** was the A3 failure in the main run (341 calls, degenerate loop on a
404 URL) a reproducible behaviour, or a one-off sample at `temperature 0.7`?

**Answer: the failure reproduces — but through a different mechanism, and the new harness did not
prevent it.**

## What changed between the two runs, and what did not

| | main run | this retest |
|---|---|---|
| Harness digest | `sha256:c88327dd3686fa75b0195481a7a045e2f899345b8c79f54a6b23a8d57ddf29e5` (built 2026-10-04) | **`sha256:3c525ab3c5d9d9c95a89797d4452e5bfd73c32de47e5b5e4fb41a6cd02dce820`** (built 2026-10-11T15:38Z) |
| dsh package content hash | `f2e66146adb3ea9f…` | **`6a043184ec7c901a…`** — genuinely different bits |
| Shipped plugins (6 tarballs) | — | **byte-identical sizes to the old image**, incl. `dsh-repeat-tool-breaker-0.8.7.tgz` |
| Image `Config` (env/entrypoint) | — | identical |
| Docker build steps | — | identical (pure rebuild) |
| **Backend container** | `b70-dev-test-b11540` @ `sha256:8bfbe375…` | **the same container, restarted — same digest** |
| `/props` readback | 0.7 / 0.80 / 20 / 0.0 / 1.5 / 0.0 / 1.0, n_ctx 131072 | **identical** |
| Largest model buffer | 17402.38 MiB unsplit | **identical** |
| A3 prompt | `a3_snowfall`, sha256 `464f1f898c978b56` | **unchanged, same source file** |

So **the harness is the only variable.** Note the caveat: because the six plugin tarballs are
byte-identical, the plugin that governs repeat-blocking did **not** change — which turned out to be
the decisive fact.

## Result

| | main run | retest |
|---|---|---|
| Outcome | no answer, terminated at 27 m 45 s | **no answer, terminated at 48 min** |
| Tool calls | 334 | **280** |
| Server requests | 341 | **281** |
| Requests / min | ~12 (failing fetches, cheap) | ~6 |
| Distinct call fingerprints | — | 122 of 280 |
| Repeated calls | ~325 × identical blocked `web_fetch` | **102 × consecutively identical `bash`** |
| `REPEAT_TOOL_BLOCKED` events | ~1 (after 5 consecutive 404s) | **5** (call indices 32, 36, 59, 101, 103) |
| Answer produced | none (log = boot banner, 376 B) | none (log = boot banner, 1881 B) |
| Metrics for the task | meaningless (loop) | **also meaningless**: 281 calls, largest prompt 58421, fill 431.85 tok/s, decode 28.75 tok/s, accept 92.2 % (31587/34269) |

## The mechanism is different, and that is the finding

**Main run.** The model fetched one dead URL (`station_34709.csv`, HTTP 404) over and over. The
breaker caught it after 5 consecutive failures and said so explicitly:

```
Failing target(s):
- exact:web_fetch:{"url":"…station_34709.csv"} — 5 consecutive failures (the request returned HTTP 404)
- host:dd.weather.gc.ca — 5 consecutive failures
This target is not going to start working because the call is rephrased.
```

…and the model re-issued the identical blocked call ~325 more times.

**Retest.** Also a loop, but a *bash* loop. From call 179 to call 280 — the final 102 calls — the
model issued a **byte-identical `python3 - <<'EOF'` heredoc** that re-parses one spooled
`web_fetch_pro` file:

```
python3 - <<'EOF'
import re
src = open('/tmp/dsh-spill-SP27Td/session-783de0790d52/ed8e907b1a8c-web_fetch_pro…
```

**The breaker never blocked any of those 102 calls.** All 5 block events in the run are
`web_fetch_pro` / `web_fetch_file` — i.e. the breaker fires on *failing network fetches*, and this
loop is a *shell command reading a local file*, so it does not match that rule. Trailing
consecutive run of the identical call: **102**, uninterrupted.

That distinction matters for triage: this is not "the model ignored the breaker" a second time. It
is **two different loop shapes, and the breaker only covers one of them**. The retest therefore
does not exonerate the new harness, and it does not specifically indict it either — the plugin
governing this rule is unchanged between the two images.

## What this run does and does not establish

- ✅ **A3 fails reproducibly** on this backend: 2/2 runs, no answer, both loops, both needing manual
  termination. The main report's FAIL stands and is now n=2.
- ✅ The new harness (`3c525ab3…`) **does not fix A3** on this build.
- ✅ A concrete, actionable defect surfaced: **the repeat-tool-breaker's coverage has a hole for
  repeated non-failing `bash` calls.** 102 identical calls in a row is exactly what a breaker is
  for. Whoever owns that plugin has a reproducible repro here — session
  `session-d89924b3-c857-4b80-a89a-00dcd950df43`, calls 179–280.
- ❌ **It does not tell us whether this is a b11540 regression.** Both runs are on the same backend
  digest. The v0.6.0 baseline passed A3 with 47 calls, but that is a different build *and* a
  different harness — a matched A/B against `b11458` (the subtree this image advanced from) is
  still the only way to attribute it to llama.cpp.
- ⚠️ Both loops are also consistent with a model-quality limit (a 27B Q4 model repeatedly failing to
  notice it is stuck), which is not a property of the SYCL backend at all.

## Cost and restoration

The card was held for 48 minutes; the retest produced no answer and was terminated by hand
(`harness rc=137`, SIGKILL — deliberate, not a crash). Server log dumped before teardown
(4,321,237 lines). Production was then restored and verified end-to-end:

| # | Check | Result |
|---|---|---|
| 1 | Worker `/health` (`:18080`) | `{"status":"ok"}` |
| 2 | Worker actually infers | `content='ok'` |
| 3 | **Through the SMG router** | real completion, not 503 |
| 4 | Router `/workers` | `:18090` + `:18080` both `healthy=True status=ready` |

**Step 4 caught a real gap again, the same way as in the main run**: right after
`docker start b70-sycl`, `/health` was already `ok` and the worker inferred, while SMG still showed
`18080=False/failed`. The breaker self-healed after ~80 s (16:34:22 failed → 16:35:42 ready), so no
`docker restart smg` was needed. Checking only `/health`, or only one routed request, would have
missed that the B70 was still out of rotation.

Final: `b70-sycl`, `xtx-vulkan`, `smg` up; `b70-sycl` and `xtx-vulkan` both `RestartCount=0`,
`OOMKilled=false`. Candidate `b70-dev-test-b11540` left stopped, not removed.
