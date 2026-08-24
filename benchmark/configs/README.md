# Configuration Reference

Each file under this directory documents one **stable, reproducible server configuration** — the exact launch flags, memory footprint, and when to use it. Reports under `benchmark/results/` link back to these files, so a config description is kept once and reused across runs.

## Quick index

| Config | Draft | Context | KV cache | Purpose |
|--------|-------|---------|----------|---------|
| [draft2b-128k](./draft2b-128k.md) | None (2B tested) | 128k | **f16** (q8_0 test) | Baseline / speculative-vs-not comparison |
| [nodraft-vision-128k](./nodraft-vision-128k.md) | No draft | 128k | f16 | Stable text + vision, no speculation |
| [mtp3-96k](./mtp3-96k.md) | BF16 MTP (n=3) | 96k | **q8_0** | **Recommended** — best stability + latency |
| [mtp4-128k](./mtp4-128k.md) | BF16 MTP (n=4) | 128k | **q8_0** | Max context + full MTP |

## Template for a new config

```markdown
# <config short name>

- Purpose: ...
- Draft: ...
- Context / KV: ...

## Full launch flags
...complete docker run / llama-server command...

## Memory footprint
Main model / draft / KV, and why it fits (or not) in 32 GB.

## When to use / avoid
...
```

**Every config must state its KV cache type** — f16 vs q8_0 is the single biggest stability lever on B70 (see `benchmark/METHODOLOGY.md` §4).