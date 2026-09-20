# Agent Test Prompt - B70 image validation

This file is the standing instruction an automated agent follows when a new
B70 image issue is opened. It is read by the `dsh-github-image-watch` webhook
rule, which passes its contents as the first prompt of a new Session, followed
by the issue metadata and body.

Keeping the instructions here rather than inside the plugin means the procedure
can evolve with the repository. The plugin falls back to an embedded copy of
this text when the file is missing.

---

Test the newly built llama.cpp SYCL B70 image described by the issue appended to
this prompt.

Work through these steps and report honestly at the end.

## 1. Identify what you are testing

- Read `docs/GOLDEN-CONFIG.md`. Every parameter comes from there; the only thing
  the issue changes is the image tag.
- Record the digest you actually pulled (`docker inspect` / the repo digest in
  the manifest), not just the tag. Tags move; a digest is the only durable
  record of what was tested.
- Note the llama.cpp build, Intel compute-runtime, IGC and Level Zero versions
  from the issue, and compare them with the previous stable baseline. A driver
  or compiler bump is a bigger change than a llama.cpp build bump and deserves
  its own line in the report.

## 2. Free the GPU deliberately

A single Arc B70 cannot host two inference containers.

- Inspect what currently holds the card (read-only: `docker ps -a`,
  `docker logs`, `docker inspect`) before changing anything.
- The production container is **production**. Never stop, restart or remove it
  without the user's explicit consent. Ask first, and name exactly which
  container you need down and for how long.

## 3. Run the full suite

- Use the isolated `dsh-container` harness. Never point a test at the production
  `~/.dsh`; every run gets its own `DSH_HOME`.
- Run the complete backend suite: the text tasks `t1`-`t5` plus the visual
  tasks `V1`-`V3`.
- Run the tasks serially. A concurrent smoke test on the same card contaminates
  timing badly enough to look like a regression.
- Before each task, record `docker logs <container> | wc -l` as a window marker
  so the metrics parser reads exactly this task's log lines.

## 4. Report per task

For every task, give:

| Field | Meaning |
|---|---|
| fill | prefill throughput, tokens/s |
| TTFT | time to first token, seconds |
| decode | generation throughput, tokens/s |
| draft acceptance | accepted / generated, block-weighted |

Then state plainly:

- any crash, OOM, restart, SIGSEGV, allocation failure, `UR_RESULT_ERROR` or
  device loss, with the log line that shows it;
- `RestartCount` and `OOMKilled` from `docker inspect`;
- a comparison against the previous stable baseline, per task.

Do not extrapolate. Report only what you measured, and say explicitly which
numbers you could not measure and why.

## 5. Decide

- If the suite is fully green, say so and state the promote decision plainly.
- If anything failed, describe the failure, keep the container for
  post-mortem, and do not promote.
- If the results are green but the change is one you judge not worth shipping,
  say that too - not shipping is a valid outcome and should be recorded as one.
