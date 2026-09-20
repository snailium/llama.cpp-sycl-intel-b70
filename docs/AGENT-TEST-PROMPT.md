# Agent Test Prompt - B70 SYCL image validation

This file is the standing instruction an automated agent follows when a new
B70 SYCL image issue is opened. It is read by the `dsh-github-image-watch` webhook
rule, which passes its contents as the first prompt of a new Session, followed by
the issue metadata and body.

Keeping the instructions here rather than inside the plugin means the procedure
can evolve with the repository. The plugin falls back to an embedded copy of this
text when the file is missing.

---

Test the newly built llama.cpp **SYCL** B70 image described by the issue appended
to this prompt.

## 0. Load the procedure skills first

Before anything else, call the `skill` tool for these, in order:

1. **`backend-test-suite`** - the card-agnostic battery: task definitions, the
   isolated harness invocation, the mandatory per-task metrics, the report template.
2. **`b70-backend-test`** - the B70 half: golden config, mandatory environment
   variables, the oneDNN/XMX and MTP pitfalls, card exclusivity.

Do not start testing before reading them. They contain the exact commands and the
failure signatures that make results interpretable.

## 1. Identify what you are testing

- Read `docs/GOLDEN-CONFIG.md`. Every parameter comes from there; the only thing
  the issue changes is the image tag.
- Record the **digest** you actually pulled (`docker inspect` / the repo digest in
  the manifest), not just the tag. Tags move; a digest is the only durable record
  of what was tested.
- Note the llama.cpp build and the Intel stack (compute-runtime, IGC, Level Zero)
  from the issue, and compare with the previous baseline. A driver or compiler bump
  is a bigger change than a llama.cpp build bump and deserves its own line in the
  report.

## 2. Free the B70 deliberately

A single Arc B70 cannot host two inference containers.

- Inspect what currently holds the card (read-only: `docker ps -a`, `docker logs`,
  `docker inspect`) before changing anything.
- The production container is **production**. Never stop, restart or remove it
  without the user's explicit consent. Ask first, and name exactly which container
  you need down and for how long.
- **The 7900 XTX container may stay running**, but both containers mount
  `/dev/dri` as a whole, so baseline the other container's `RestartCount` before the
  run and re-check after — a value that grew means the run leaked outside its card.

## 3. Run the full suite

- Use the isolated `dsh-container` harness. Never point a test at the production
  `~/.dsh`; every run gets its own `DSH_HOME`.
- Run the complete battery: the text tasks `t1`-`t5` plus the visual tasks `V1`-`V3`.
- Run the tasks **serially**. A concurrent smoke test on the same card contaminates
  timing badly enough to look like a regression.
- Before each task, record `docker logs <container> | wc -l` as a window marker so
  the metrics parser reads exactly this task's log lines.

## 4. Report per task

For every task, give:

| Field | Meaning |
|---|---|
| fill | prefill throughput, tokens/s |
| TTFT | time to first token, seconds |
| decode | generation throughput, tokens/s |
| draft acceptance | accepted / generated, block-weighted |

Then state plainly:

- any crash, OOM, restart, SIGSEGV, allocation failure, `UR_RESULT_ERROR` or device
  loss, with the log line that shows it;
- `RestartCount` and `OOMKilled` from `docker inspect`;
- a comparison against the previous stable baseline, per task.

**Watch for the memory-splitting trap.** Upstream reduced the B70's maximum single
allocation as a workaround for an open compute-runtime bug, so a large model can
newly cross that line and get split across buffers. Check
`load_tensors: SYCL0 model buffer size` — if the biggest buffer got split, decode
drops even though no kernel changed, and that is not a real regression.

Do not extrapolate. Report only what you measured, and say explicitly which numbers
you could not measure and why.

## 5. Decide

- If the suite is fully green, say so and state the promote decision plainly.
- If anything failed, describe the failure, keep the container for post-mortem, and
  do not promote.
- If the results are green but the change is one you judge not worth shipping, say
  that too - not shipping is a valid outcome and should be recorded as one.

This repository has one card and one channel per issue, so the gate is simple:
**B70 must pass.** (The Vulkan repository is the one with a per-channel gate across
two cards - see its own `AGENT-TEST-PROMPT.md`.)
