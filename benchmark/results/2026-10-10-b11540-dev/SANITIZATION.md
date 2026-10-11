# Sanitization applied before publishing this archive

This archive is committed to a **public** repository, so the internal identifiers that appear
in the raw run output were replaced with neutral placeholders before commit. The repo's own
rule (`docs/GOLDEN-CONFIG.md`): *"this repo is public — never commit internal IPs, usernames,
or absolute host paths here."*

| kind of value | replaced with | occurrences |
|---|---|---|
| GPU-host IPv4 address | a **RFC 5737 TEST-NET-1** address (`192.0.2.0/24`) | 7 |
| GPU-host alias | `gpu-host` | 2 |
| control-host alias | `control-host` | 9 |
| workspace absolute path | `<workspace>` | 7 |
| DSH skills absolute path | `<dsh-skills>` | 1 |
| home-directory absolute path | `<home>` | 2 |

The original strings are deliberately **not reproduced in this file** — the whole point of the
exercise is that they do not land in a public repo, and a mapping table would defeat it. The
substituted addresses come from `192.0.2.0/24`, which is reserved for documentation, so they
are unmistakably non-routable and cannot be mistaken for a real host. The host octet is kept
so port mappings (`…:18080`, `…:18082`, `…:18090`) stay readable.

## What was done

- Substitution applied to **both** the decompressed `.jsonl` session records **and** their
  `.zstd` siblings. The compressed copies were **regenerated from the sanitized `.jsonl`**,
  not left in place — otherwise the byte-exact original (identifiers included) would still
  have been committed inside the compressed stream. This was caught in review: the first pass
  rewrote the `.jsonl` files and left two `.zstd` files carrying the originals.
- Each `.zstd` was then verified to decompress to exactly its `.jsonl` (`cmp` on the
  decompressed stream), so every pair is consistent.
- Verified over **all** files three ways: as text, as decompressed zstd, and via `strings`
  over the raw bytes of every file.

## What was deliberately NOT changed

Public or non-identifying values that would lose meaning if altered:

- **Container names** (`b70-sycl`, `b70-dev-test-b11540`, `xtx-vulkan`, `smg`) — they appear
  throughout this repo's own docs and describe the experiment, not the host.
- **Ports** (18080 / 18082 / 18090 / 40114) — needed to read the restore-verification evidence.
- **Model / image paths** under `/models` and `ghcr.io/...` — public artifacts.
- **E-mail addresses found in fetched web pages** — public upstream contacts that arrived via
  tool output, not data from this environment.
- **Log prefixes such as `10.00.963.191`** — these are `HH.MM.SS.mmm` timestamps, not IP
  addresses. A naive private-range scan false-positives on them; they were left alone.

## Reproducibility note

The substitution is a search-and-replace over evidence, so the **numbers, timings and
conclusions are unchanged**. Only host identification is generalised. `sanitize.py` is the
script that was used, with its own mapping table redacted for the same reason as above — read
it as "internal host → documentation placeholder".
