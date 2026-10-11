#!/usr/bin/env python3
"""Desensitize the issue #29 archive before committing it to a PUBLIC repo.

The repo's own rule (docs/GOLDEN-CONFIG.md header) is explicit:

    Host placeholders are used on purpose: this repo is public -- never commit
    internal IPs, usernames, or absolute host paths here.

So this replaces, consistently and reversibly-in-documentation:

  * internal IPv4 addresses        -> RFC 5737 documentation ranges
  * the two host aliases           -> generic role names
  * absolute home paths            -> a workspace-relative placeholder

Both the decompressed .jsonl and its byte-exact .zstd sibling are rewritten, so
the pair stays consistent (the .zstd must be regenerated from the rewritten
.jsonl, otherwise it would still carry the original bytes).

Mapping is printed so the report can document it.
"""
import os
import re
import subprocess
import sys

ARCH = sys.argv[1] if len(sys.argv) > 1 else "."
DRY = "--dry-run" in sys.argv

# --- substitution table -------------------------------------------------------
# Internal IPs -> RFC 5737 TEST-NET-1 (192.0.2.0/24), which is reserved for
# documentation. The host octet is kept so the port mapping stays readable.
# The real table is redacted here on purpose: this file is committed to a public
# repo, so reproducing the original identifiers would undo the sanitisation it
# documents. Read it as "internal host -> documentation placeholder".
IP_MAP = {
    "<GPU_HOST_IP>": "192.0.2.101",      # GPU host      -> TEST-NET-1
    "<CONTROL_HOST_IP>": "192.0.2.90",   # control host  -> TEST-NET-1
}
# Host aliases -> role names.
HOST_MAP = [
    ("<GPU_HOST_ALIAS>", "gpu-host"),
    ("<CONTROL_HOST_ALIAS>", "control-host"),
]
# Absolute paths -> workspace-relative placeholders.
PATH_MAP = [
    ("<HOME>/deepseek-workspace/llama.cpp", "<workspace>"),
    ("<HOME>/.dsh/skills", "<dsh-skills>"),
    ("<HOME>/.dsh", "<dsh-home>"),
    ("<HOME>", "<home>"),
]

TEXT_EXT = {".md", ".json", ".jsonl", ".txt", ".py", ".sh", ".html", ".svg", ".yml", ".yaml"}


def bump(counters, key, n):
    if n:
        counters[key] = counters.get(key, 0) + n


def sanitize(text: str, counters: dict) -> str:
    for a, b in IP_MAP.items():
        n = text.count(a)
        bump(counters, f"ip:{a}", n)
        if n:
            text = text.replace(a, b)
    for a, b in HOST_MAP:
        # Plain token replacement, deliberately WITHOUT word-boundary lookarounds.
        # Measured reason: in the session .jsonl these aliases sit inside JSON
        # string escapes -- "=== Hostname ===\\n<ALIAS>\\n===" -- where the
        # preceding character is the literal 'n' of the \\n escape. A (?<![\\w])
        # lookbehind therefore refuses to match and the alias survives
        # sanitisation. These aliases are distinctive enough for a bare replace.
        n = text.count(a)
        bump(counters, f"host:{a}", n)
        if n:
            text = text.replace(a, b)
    for a, b in PATH_MAP:
        n = text.count(a)
        bump(counters, f"path:{a}", n)
        if n:
            text = text.replace(a, b)
    return text


def main():
    counters = {}
    changed = []
    # group .jsonl with its .zstd so we rewrite the jsonl once and rebuild zstd
    entries = sorted(os.listdir(ARCH))
    zstd_of = {}
    for fn in entries:
        if fn.endswith(".jsonl.zstd"):
            zstd_of[fn[: -len(".zstd")]] = fn

    for fn in entries:
        p = os.path.join(ARCH, fn)
        if not os.path.isfile(p):
            continue
        ext = os.path.splitext(fn)[1]
        if ext == ".zstd":
            continue  # handled with its .jsonl sibling
        if ext not in TEXT_EXT:
            continue
        before = open(p, encoding="utf-8", errors="surrogateescape").read()
        after = sanitize(before, counters)
        zstd_name = zstd_of.get(fn)
        if after != before or zstd_name:
            changed.append(fn)
            if not DRY:
                open(p, "w", encoding="utf-8", errors="surrogateescape").write(after)
                # regenerate the zstd sibling from the sanitized jsonl so the
                # compressed copy cannot still carry the original bytes
                if zstd_name:
                    r = subprocess.run(
                        ["zstd", "-q", "-f", "-19", p, "-o", os.path.join(ARCH, zstd_name)],
                        capture_output=True, text=True,
                    )
                    if r.returncode != 0:
                        raise SystemExit(f"zstd regen FAILED for {zstd_name}: {r.stderr[:200]}")
                    print(f"  zstd regenerated: {zstd_name}")
    print("=== substitution counts ===")
    for k, v in sorted(counters.items()):
        print(f"  {k:44} {v}")
    print(f"\n=== files rewritten: {len(changed)} ===")
    for c in changed:
        print(f"  {c}")


if __name__ == "__main__":
    main()
