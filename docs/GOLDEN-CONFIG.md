# Golden configuration — B70 production stack

> **This is the single source of truth for what we actually deploy.** Everything else in this
> repository is evidence, history, or experiment. If a document disagrees with this file, this
> file wins (and the other document should be dated/superseded).
>
> As of **2026-09-20** (llama.cpp **v0.4.1**, promoted from issue #18).
> Host placeholders are used on purpose: this repo is public — **never commit internal IPs,
> usernames, or absolute host paths here.**

## 1. Image

| Item | Value |
|---|---|
| Image (pinned) | `ghcr.io/snailium/llama.cpp-sycl-intel-b70/llama-sycl-b70:server-c26.35.39758.10-v0.5.0` |
| Image (floating) | `…:stable` |
| Digest (both tags) | `sha256:a7106ff20d67f1784bde2c5e2cdcf4fc0dc7fabb13161b62acef338313f85a79` |
| llama.cpp | v0.5.0 (in-image `libllama.so.0.5.0` / `libggml-base.so.0.25.1`) |
| Intel stack | compute-runtime `26.35.39758.10` (`libze_intel_gpu.so.1.17.39758`) / IGC `v2.41.5+1788943183` / Level Zero loader `1.32.0` |
| oneDNN / XMX | `-DGGML_SYCL_DNN=ON`; `libdnnl.so.3` linked; runtime gate `GGML_SYCL_FA_ONEDNN` **defaults to 1** |
| Entrypoint | `/app/llama-server` (image default — **never override it**) |
| Rollback point | `sha256:d7f303202d55357da11e3e6f0c7dae3bed6f381dbeb930ead4208d0fcb1742f5` (v0.4.1) |

Promoted 2026-09-24 from issue [#21](https://github.com/snailium/llama.cpp-sycl-intel-b70/issues/21)
via `promote-stable.yml`, with the digest guard set to the tested digest. Validated by **two**
independent full-suite passes — see [`benchmark/results/2026-09-23-issue21-v050-stable.md`](../benchmark/results/2026-09-23-issue21-v050-stable.md)
and [`…-retest.md`](../benchmark/results/2026-09-23-issue21-v050-retest.md).

The Intel stack is **byte-identical** to the previous stable, so this is a **llama.cpp-only change**
(v0.4.1 → v0.5.0); the two passes bracket the baseline on every task, i.e. no measured regression.

> ⚠️ **The promoted image predates the `DEBUG_FLAG` change (commit `f0cf4df`).** Its entrypoint is
> still `["/app/llama-server"]`, so `-e DEBUG_FLAG=-v` is **inert** on this digest — pass `-v` as a
> real argument, or rebuild. See §2.1.

Verify a pulled image before serving:

```bash
docker run --rm --entrypoint /bin/bash <image> -lc '
  ldd /app/libggml-sycl.so | grep -i dnnl
  strings /app/libggml-sycl.so | grep -m1 g_ggml_sycl_fa_onednn'
```

## 2. Container spec

```bash
docker run -d --name b70-llama-golden \
  --device /dev/dri \
  -v <models-dir>:/models:ro \
  -p 18082:8080 \
  -e ONEAPI_DEVICE_SELECTOR=level_zero:0 \
  -e SYCL_CACHE_PERSISTENT=0 \
  -e ZES_ENABLE_SYSMAN=1 \
  $(sed 's/^/  -e /' <server-env — see §3>) \
  --restart no \
  <image>
```

There is no `command:` — every server parameter is an `LLAMA_ARG_*` environment
variable (§3). Use `docker-compose.yml` or `examples/qwen27b-server.sh`, both of
which already do this.

The one **non-`LLAMA_ARG_*`** variable is `DEBUG_FLAG` (see §2.1) — it exists
because `-v` has no environment-variable mapping upstream.

| Setting | Value | Why |
|---|---|---|
| Device | `/dev/dri` (whole directory) | the Arc GPU is `renderD128`; passing the directory survives card index changes |
| Models | host models dir mounted **read-only** at `/models` | weights never need to be writable |
| Port | host `18082` → container `8080` | 8080 stays free on the host |
| `ONEAPI_DEVICE_SELECTOR` | `level_zero:0` | pin to the discrete GPU (host also has an AMD iGPU) |
| `SYCL_CACHE_PERSISTENT` | `0` | **mandatory** — `1` SIGSEGVs on Xe2 during first JIT |
| `ZES_ENABLE_SYSMAN` | `1` | sysman queries (memory/utilisation) |
| `GGML_SYCL_FA_ONEDNN` | *unset* (defaults to `1`) | XMX SDPA path; only set it explicitly to force `0` for A/B |
| `DEBUG_FLAG` | `""` default; set `-v` to enable verbose logging | see §2.1 — the only way to get `-v` into argv from the environment |
| `--restart` | `no` | deliberate: GPU containers must be brought up consciously after host/PCIe events |

### 2.1 `DEBUG_FLAG` — how `-v` reaches the binary

**`-v` is the only llama.cpp server argument with no `.set_env(...)` mapping.**
In `common/arg.cpp` it is declared as

```cpp
add_opt(common_arg(
    {"-v", "--verbose", "--log-verbose"},
    "Set verbosity level to infinity (i.e. log all messages, useful for debugging)",
    [](common_params & params) { params.verbosity = INT_MAX; ... }
));                       // <-- no .set_env(...)
```

so **no environment variable will turn it on**:

| Attempt | Result |
|---|---|
| `ENV LLAMA_ARG_VERBOSE=1` | **silently ignored** — no such variable exists upstream |
| `ENV LLAMA_ARG_LOG_VERBOSITY=5` | sets a *numeric threshold*; does **not** produce the per-request `print_timing` lines |
| `ENV DEBUG_FLAG=-v` | ✅ works — the image entrypoint injects it into argv |

The `server` stage therefore wraps the binary:

```dockerfile
ENV DEBUG_FLAG=""
ENTRYPOINT [ "/bin/sh", "-c", "exec /app/llama-server $DEBUG_FLAG \"$@\"", "--" ]
```

`DEBUG_FLAG` is word-split (deliberately unquoted), so:

- empty or unset → contributes **no argument at all** (the default path is unaffected);
- `DEBUG_FLAG=-v` → `-v` is inserted *before* the caller's own arguments;
- more than one flag is possible, e.g. `DEBUG_FLAG="-v --log-colors off"`.

⚠️ **The trailing `"--"` inside `ENTRYPOINT` is required, and is not a Docker
separator.** `sh -c 'cmd' name arg1 …` puts `name` in `$0` and `arg1…` in `$@`, so
the literal `--` is just the `$0` placeholder; without it `$0` would swallow the
caller's first real argument.

⚠️ **Do NOT put a `--` on the `docker run` command line.** That one *is* a real
argument, llama-server reads it as an option name, and the container dies at boot:

```
$ docker run … <image> -c 'exec /app/llama-server $DEBUG_FLAG "$@"' -- 
warn: LLAMA_ARG_CTX_SIZE environment variable is set, but will be overwritten by
      command line argument -c
error while handling argument "-c": stoi          # ExitCode=1
```

Verified against the released v0.5.0 image, both the failure and the fix.

Usage:

```bash
docker run -d ... -e DEBUG_FLAG=-v <image>
# docker-compose.yml:  - DEBUG_FLAG=${DEBUG_FLAG:-}
```

**Verification performed** (released `sha256:a7106ff2…` image, `/bin/sh` = dash):

| `DEBUG_FLAG` | resulting argv |
|---|---|
| unset | `--model … --ctx-size …` — **no extra argument** |
| `""` | `--model … --ctx-size …` — **no extra argument** |
| `-v` | `-v --model … --ctx-size …` |
| `-v --log-colors off` | `-v --log-colors off --model …` |
| `-v`, no user args | `-v` |

End-to-end with a real server: `DEBUG_FLAG=-v` produced **6100 log lines and 4
`print_timing` records** for one request, versus **13 lines and 0 records** without
it — i.e. exactly the acceptance data that is otherwise unrecoverable.

**Why this is not cosmetic.** Without `-v` the server log is ~13 lines and
**agent-task (t3-t5) draft acceptance is unrecoverable** — those rates exist *only*
in the server's `print_timing` output, because for agent tasks the dsh harness is the
client and never sees the response-body `timings` block. One B70 run
(2026-09-20) removed its container before dumping the log and lost three rows
permanently. With `DEBUG_FLAG=-v` the variable is a container setting rather than a
step someone has to remember.

⚠️ **`-v` makes log lines contain full request bodies** (MBs per call). Bound output
width when grepping, and note that a single request body is **one enormous line** —
`wc -l` is useless as a progress window; use the `print_timing` count instead.

## 3. Server arguments (golden, exact)

The canonical form is **`LLAMA_ARG_*` environment variables**, because llama.cpp
maps every server argument to one. `docker-compose.yml` and
`examples/qwen27b-server.sh` both use this form; no flags are passed at all.

```bash
LLAMA_ARG_MODEL=/models/Qwen3.8-27B-Q4_K_M.gguf
LLAMA_ARG_MMPROJ=/models/mmproj-Qwen3.8-27B-Q8_0.gguf
LLAMA_ARG_MMPROJ_OFFLOAD=false          # == --no-mmproj-offload
LLAMA_ARG_IMAGE_MIN_TOKENS=1024
LLAMA_ARG_N_GPU_LAYERS=999
LLAMA_ARG_CTX_SIZE=131072
LLAMA_ARG_CACHE_TYPE_K=q8_0
LLAMA_ARG_CACHE_TYPE_V=q8_0
LLAMA_ARG_FLASH_ATTN=on
LLAMA_ARG_SPEC_DRAFT_MODEL=/models/mtp-Qwen3.8-27B-Q8_0.gguf
LLAMA_ARG_SPEC_TYPE=draft-mtp
LLAMA_ARG_SPEC_DRAFT_N_MAX=3
LLAMA_ARG_SPEC_DRAFT_P_MIN=0.1
LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_K=q8_0
LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_V=q8_0
LLAMA_ARG_REASONING=off
LLAMA_ARG_CHAT_TEMPLATE_KWARGS={"enable_thinking":false,"preserve_thinking":false}
LLAMA_ARG_N_PARALLEL=1
LLAMA_ARG_TEMPERATURE=0.7
LLAMA_ARG_TOP_P=0.80
LLAMA_ARG_TOP_K=20
LLAMA_ARG_MIN_P=0.0
LLAMA_ARG_PRESENCE_PENALTY=1.5
LLAMA_ARG_FREQUENCY_PENALTY=0.0
LLAMA_ARG_REPEAT_PENALTY=1.0
LLAMA_ARG_HOST=0.0.0.0
LLAMA_ARG_PORT=8080
```

Plus the runtime variables from §2 (`ONEAPI_DEVICE_SELECTOR`,
`SYCL_CACHE_PERSISTENT`, `ZES_ENABLE_SYSMAN`) and `DEBUG_FLAG` from §2.1.

### ⚠️ `SPEC_DRAFT_CACHE_TYPE_K/V` — the draft-KV variable name is easy to get wrong

The two draft-KV variables are spelled **`LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_K`** and
**`_V`**, *not* `LLAMA_ARG_SPEC_DRAFT_TYPE_K/_V`. This document carried the wrong
names until 2026-09-23, and because an unknown `LLAMA_ARG_*` variable is **silently
ignored** — no warning, no error — a run that delivered the draft KV through those
*wrong env-var names* would fall back to the **f16 default** while the docs claimed
`q8_0`.

**No recorded measurement was affected.** Every baseline run predates the env-var
form and passed the draft KV as a **flag** —

```bash
# start-v041-prodparams.sh (v0.4.1 production-params run)
--spec-draft-type-k q8_0 --spec-draft-type-v q8_0
```

— and `--spec-draft-type-k` is the correct flag spelling (only the *env var* differs,
see below). Confirmed against the baseline's own server log rather than inferred from
docs: `test-v041/server-v041.log` → `cache_k=q8_0, cache_v=q8_0`. So the baselines,
and both issue #21 validation passes, all ran the draft KV at **q8_0** (272 MiB). This
was a latent trap in the env-var form, not a defect in any past result.

The confusion is upstream's, not ours: the CLI flag and the env var deliberately
differ in shape.

```cpp
// common/arg.cpp
add_opt(common_arg(
    {"--spec-draft-type-k", "-ctkd", "--cache-type-k-draft"}, "TYPE", ...
).set_env("LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_K"));
//            ^^^^ flag reads "type"          ^^^^ env reads "cache_type"
```

Confirmed by enumerating the env-var strings out of the shipped libraries of both
the v0.4.1 baseline (`sha256:d7f30320…`) and the v0.5.0 candidate
(`sha256:a7106ff2…`) — both expose only `…_CACHE_TYPE_K/_V`, so this was
**pre-existing and is not a v0.5.0 regression**.

Verify what the server actually took, rather than trusting this file:

```bash
docker logs <container> 2>&1 | grep 'spec common_specu: - gpu_layers'
# want: cache_k=q8_0, cache_v=q8_0
# wrong name => cache_k=f16, cache_v=f16  (and the draft KV buffer is 512 MiB, not 272 MiB)
```

### ⚠️ Minimum llama.cpp version for the env-var form

**The six sampling variables are NOT supported before b11078.**

| Variable group | Minimum version |
|---|---|
| model / ctx / KV / flash-attn / offload / mmproj / spec-decode / parallel / host / port | older than v0.4.1 |
| **`LLAMA_ARG_TEMPERATURE`, `TOP_P`, `MIN_P`, `PRESENCE_PENALTY`, `FREQUENCY_PENALTY`, `REPEAT_PENALTY`** | **>= b11078** |

The six were added in commit `e0dff5847` ("args: add env vars for temperature,
top-p, min-p and penalties", #27380), first shipped in **b11078**.

Consequences, all verified against the tree rather than assumed:

- **v0.4.1 (b10964) and everything older does not support them.** They are
  **silently ignored** — no warning, no error — and the server falls back to its
  own defaults (`temp 0.8`, `top_p 0.95`, ...), which changes output quality
  without any signal. The `:stable` tag was v0.4.1 when this was written.
- **Any dev build before b11078 has the same gap.**
- **v0.5.0 (>= b11146) is fine**, as is the dev image built from b11117+.

For an older image, pass the six as flags instead — they take precedence over the
env vars, so both forms can coexist safely:

```bash
--temp 0.7 --top-p 0.80 --top-k 20 --min-p 0.0
--presence-penalty 1.5 --frequency-penalty 0.0 --repeat-penalty 1.0
```

`examples/qwen27b-server.sh` does this automatically via `USE_SAMPLING_FLAGS=1`.

Verify what the server actually accepted rather than trusting the config — read it
back from the running server:

```bash
curl -s http://127.0.0.1:8080/props | python3 -c "
import json,sys; d=json.load(sys.stdin)
p=d['default_generation_settings']
print('n_ctx =', p['n_ctx'])
for k in ('top_p','top_k','min_p','presence_penalty','frequency_penalty','repeat_penalty'):
    print(f'  {k:20} = {p[\"params\"].get(k)}')
"
```

Rationale, group by group:

- **Context / KV** — `131072` context with **`q8_0` KV**. q8_0 halves KV versus f16 and is what makes
  full 128k + a speculative draft fit in 32 GB. (f16 is the native no-dequant path for the oneDNN
  SDPA kernel, but it costs ~2× KV; see `docs/B70-TUNING.md`.)
- **Speculative decoding** — MTP head as a **separate Q8_0 draft model**, `--spec-draft-n-max 3`.
  MTP3 beats MTP4 on agent workloads (position-4 acceptance collapses); the draft uses q8_0 KV for
  the same VRAM reason as the main model.
- **Vision** — mmproj stays on the **CPU** (`--no-mmproj-offload`) with `--image-min-tokens 1024`.
- **Thinking** — `--reasoning off` (response-parsing layer) **and** a template-level
  `enable_thinking:false` default. Both are needed: the first controls where thoughts are placed,
  the second stops Qwen from generating them at all.
- **Sampling** — official Qwen3.8-27B non-thinking parameters (`presence_penalty 1.5` is Qwen's own
  fix for verbosity — do not lower temperature instead).
- **`-v`** — verbose logging. Note this makes log lines **contain full request bodies**; always bound
  output width when grepping.

## 4. Model files

| File | Size | Role |
|---|---|---|
| `Qwen3.8-27B-Q4_K_M.gguf` | 17.67 GB | main model (arch `qwen35`, dense, 64 layers) |
| `mmproj-Qwen3.8-27B-Q8_0.gguf` | 0.59 GB | vision projector |
| `mtp-Qwen3.8-27B-Q8_0.gguf` | 2.95 GB | MTP speculative head (separate GGUF, 18 tensors) |

The main GGUF carries **no** NextN layers — the MTP head lives only in the draft file.

## 5. Bring-up and verification

```bash
# 1) readiness: /health 503 ("Loading model") is normal — poll /v1/models until 200
until [ "$(curl -s -o /dev/null -w '%{http_code}' http://<b70-host>:18082/v1/models)" = 200 ]; do sleep 10; done

# 2) first completion must return 200
curl -s http://<b70-host>:18082/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model":"/models/Qwen3.8-27B-Q4_K_M.gguf",
  "messages":[{"role":"user","content":"reply with exactly: ok"}],
  "max_tokens":16,"chat_template_kwargs":{"enable_thinking":false}}'

# 3) thinking really off: reasoning_content must be absent/null in the response
# 4) stability after a load: RestartCount=0, no OOMKilled
docker inspect <container> --format 'restart={{.RestartCount}} status={{.State.Status}} oom={{.State.OOMKilled}}'
```

Model load takes ~2 minutes (17.7 GB main + draft + mmproj) before `/v1/models` answers 200.

## 6. Expected performance (v0.4.1 full suite, golden config)

Measured 2026-09-14 on a single Arc Pro B70 with the exact configuration above, on the
compute-runtime `26.31.39395.13` artifact. Superseded runs on `26.35.39758.10` (issues #18, #19)
found these numbers **unchanged within noise** — see each report's comparison table.
Full report: [`benchmark/results/2026-09-14-v041-stable.md`](../benchmark/results/2026-09-14-v041-stable.md).

| Task | fill (tok/s) | TTFT med/mean | decode (tok/s) | draft acc |
|---|---|---|---|---|
| t1_html | 64.0 (43-tok prompt) | 0.67 s | 41.4 | 0.744 |
| t2_svg | 49.5 (32-tok prompt) | 0.65 s | 46.2 | 0.897 |
| t3_security (agent) | 472.3 | 3.90 / 9.12 s | 20.82 | 0.532 |
| t4_hostinfo (agent) | 492.2 | 3.55 / 8.24 s | 37.57 | 0.809 |
| t5_snowfall (agent) | 298.6 | 0.96 / 1.59 s | 33.93 | 0.812 |
| V1 game (vision) | 32.5 | 110.8 s | 34.1 | 0.574 |
| V2 pcb (vision) | 59.3 | 18.6 s | 36.8 | 0.606 |
| V3 tire (vision) | 29.6 | 141.0 s | 40.1 | 0.733 |

Reading the numbers:

- **Text prefill (fill)** is the XMX/oneDNN SDPA path — 470–490 tok/s weighted on agent tasks,
  570–600 tok/s in bursts. Quantized KV gets there via dequantize→f16 followed by SDPA (upstream
  #25874, merged 2026-08-04).
- **Decode** is memory-bound: 40–46 tok/s on short contexts, ~21 tok/s at the deep end of a long
  agent task. This is the structural ceiling for a single stream on this part (upstream #26581) —
  aggregate throughput via concurrency is where the headroom is.
- **Vision** prefill is slow (mmproj on CPU + image encoding): 18–141 s TTFT, but decode after the
  image is normal (34–40 tok/s) and speculation keeps working.
- **Draft acceptance** 0.53–0.90 depending on task shape; MTP3 avoids the position-4 collapse.

## 7. Stability assertions

- `RestartCount=0`, `OOMKilled=false` across the full suite.
- Zero occurrences of SIGSEGV / allocation failure / `UR_RESULT_ERROR*` / device-lost / GPU hang in
  the server log.

## 8. Operational rules

1. **The B70 containers are production.** Never restart, stop, remove, or rebuild them without
   explicit user consent. Read-only inspection (`docker logs`, `docker inspect`, `docker ps`) is fine.
2. **One GPU, one server.** A second llama.cpp container cannot co-exist with this one on the single
   card (VRAM), so a test image must replace it — not run beside it.
3. **Promote by digest, never by moving a tag by hand** — run `promote-stable.yml` with
   `expected_digest` set to the tested digest; the workflow verifies it and refuses a mismatch.
4. **Rollback point**: `sha256:d7f303202d55357da11e3e6f0c7dae3bed6f381dbeb930ead4208d0fcb1742f5`
   (v0.4.1, the stable this replaced on 2026-09-24). Roll back by stopping the current container and
   starting one from that digest. (Older: `sha256:5af1e229…`, compute-runtime `26.31.39395.13`, the
   last pre-driver-bump stable.)
5. Any configuration change gets its own dated entry below, and any superseded document gets a
   `Superseded by …` line at the top.

## 9. Mirrors of this configuration

| File | Role |
|---|---|
| [`examples/qwen27b-server.sh`](../examples/qwen27b-server.sh) | bare-metal launcher mirroring §3 exactly |
| [`docker-compose.yml`](../docker-compose.yml) | container definition mirroring §2 + §3 |
| [`benchmark/configs/golden-v041-q8-128k-mtp3.md`](../benchmark/configs/golden-v041-q8-128k-mtp3.md) | config record with the measured numbers |
| [`LEVEL-ZERO-VERSION-DISCREPANCY.md`](LEVEL-ZERO-VERSION-DISCREPANCY.md) | why the image shipped L0 1.28.6 while CI reported 1.32.0 — **fixed as of the 2026-09-23 b11117 candidate, which ships `libze1 1.32.0`** |

## Change log

| Date | Change |
|---|---|
| 2026-09-14 | Golden established: v0.4.1 (`:stable`), q8_0 KV / 128k / MTP3 + Q8_0 draft, reasoning off. Promoted from issue #17 after a full 3-vision + 5-text pass. Replaces the v0.3.0-era "F16 KV + 96k + Q4_0 MTP" recommendation (kept below as history). |
| 2026-09-20 | `:stable` re-pointed to the issue-#18 artifact (compute-runtime `26.35.39758.10`, IGC `v2.41.5`, digest `sha256:d7f30320…`). Image/digest/§6 provenance rows updated to match what production actually serves — they had drifted a release behind. |
| 2026-09-20 | Level Zero recorded as **loader `1.28.6`**, not the `1.32.0` CI reports. The image is built on a base that already ships L0 1.28.6, and the oneAPI install in the same stage displaces the CI-pinned 1.32.0 packages. Driver (`26.35.39758.10`) and IGC (`2.41.5`) are unaffected. Root cause and evidence: [`LEVEL-ZERO-VERSION-DISCREPANCY.md`](LEVEL-ZERO-VERSION-DISCREPANCY.md). |
| 2026-09-20 | Issue #19 dev candidate (`60081bb`, digest `sha256:4dc70c03…`) passed the full battery 8/8 with zero crashes; **not** promoted to `:stable` (parity, no stated reason for the llama.cpp bump). Published as `:server-dev` + `:server-dev-b11046-c26.35.39758.10`. Report: [`benchmark/results/2026-09-20-issue19-b11046-dev.md`](../benchmark/results/2026-09-20-issue19-b11046-dev.md). |
| 2026-09-23 | Issue #20 dev candidate (b11117, digest `sha256:30159fab…`) passed the full battery 8/8 with zero crashes, no buffer splitting, and no prefill regression (±3 %). **First image in which the Level Zero packaging fix is actually present**: it ships loader `1.32.0` (was `1.28.6` in #18/#19), so this candidate moves both the llama.cpp build and the L0 loader — see the note on the §9 `LEVEL-ZERO-VERSION-DISCREPANCY.md` row below. **Not** promoted to `:stable`; dev channel only, pending a second clean pass on the same digest and a stated reason for the loader bump. Report: [`benchmark/results/2026-09-23-issue20-b11117-dev.md`](../benchmark/results/2026-09-23-issue20-b11117-dev.md). |
| 2026-09-23 | **§3 rewritten to the `LLAMA_ARG_*` environment-variable form**; `docker-compose.yml` and `examples/qwen27b-server.sh` now pass **no flags at all**. Verified end-to-end on b11117: launched with env only, then read the values back from `/props` (`n_ctx 131072`, `top_p 0.80`, `top_k 20`, `min_p 0.0`, `presence_penalty 1.5`, `frequency_penalty 0.0`, `repeat_penalty 1.0`) and ran a real completion. Added the **version floor**: the six sampling variables need **>= b11078** (commit `e0dff5847`, #27380) and are *silently ignored* on v0.4.1 and older, so `USE_SAMPLING_FLAGS=1` exists for old images. |
| 2026-09-23 | **Corrected the draft-KV variable names to `LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_K/_V`** (§3) — the previous `…_SPEC_DRAFT_TYPE_K/_V` does not exist upstream and is silently ignored, so an env-var-form launch using those names would run the draft KV at f16 while the docs claimed q8_0. Fixed in `GOLDEN-CONFIG.md`, `docker-compose.yml` and `examples/qwen27b-server.sh`. **No past measurement was affected** — every baseline ran the draft KV via the *flag* form (`--spec-draft-type-k q8_0`), confirmed from `test-v041/server-v041.log` (`cache_k=q8_0`). Found during the issue #21 v0.5.0 validation; pre-existing, not a v0.5.0 regression. |
| 2026-09-23 | **Added `DEBUG_FLAG` to the `server` Dockerfile stage (§2.1)** — `-v` is the only server argument with no `.set_env()` upstream, so it can only reach the binary via argv; the image entrypoint now injects it from a container variable (`-e DEBUG_FLAG=-v`). Default empty means no behaviour change. Without it, agent-task draft acceptance is unrecoverable. ⚠️ **The image promoted below predates this change, so `DEBUG_FLAG` is inert on it — rebuild required.** |
| 2026-09-24 | **PROMOTED issue #21 candidate to `:stable`** — `sha256:a7106ff2…` (llama.cpp **v0.5.0**), replaced `sha256:d7f30320…` (v0.4.1). Intel stack byte-identical to the outgoing stable, so this is a **llama.cpp-only change**. Validated by two independent full-suite passes (`2026-09-23-issue21-v050-stable.md` + `…-retest.md`): 8/8 tasks, zero crash/OOM/device-loss signatures over ~1.35 M log lines across both runs, unsplit 17402.38 MiB main buffer, `RestartCount=0`. The first pass flagged a 4–6 % decode delta below baseline; the **second pass at matched draft-KV precision showed it was noise** and retracted it. Two operational findings recorded as open issues rather than blockers: **t5 answer variance** (same digest answered 258.6 mm vs 217.0 cm — the latter a 10× unit error) and **SMG not self-healing** after a worker restart (worker `/health` ok while `/workers` reported `failed`; failover masked it; `docker restart smg` cleared it). |
