#!/usr/bin/env python3
"""Parse llama-server `slot print_timing` blocks into per-request records.

A block is 6 consecutive print_timing lines; the `draft acceptance` line closes
it, so the number of `draft acceptance` lines is exactly the number of finished
requests -- which is also the per-task window marker used by the drivers.

Reported per task window:
  fill   = sum(prompt_n) / sum(prompt_ms) * 1000        (tokens/s)
  decode = sum(predicted_n) / sum(eval_ms) * 1000       (tokens/s)
  accept = sum(accepted) / sum(generated), with K
"""
import os
import re
import sys
import json

HERE = os.path.dirname(os.path.abspath(__file__))
RUNDIR = open(os.path.join(HERE, "CURRENT_RUNDIR")).read().strip()
LOGDIR = os.path.join(RUNDIR, "logs")

NUM = r"([0-9.]+)"

RE_PROMPT = re.compile(r"task (\d+) \| prompt eval time =\s*" + NUM + r" ms /\s*(\d+) tokens")
RE_EVAL = re.compile(r"task (\d+) \|        eval time =\s*" + NUM + r" ms /\s*(\d+) tokens")
RE_ACC = re.compile(
    r"task (\d+) \| draft acceptance = " + NUM + r"\s*\(\s*(\d+) accepted /\s*(\d+) generated\)"
)


def parse(path):
    blocks = []
    cur = {}
    for line in open(path, errors="replace"):
        m = RE_PROMPT.search(line)
        if m:
            cur = {"task": int(m.group(1)), "prompt_ms": float(m.group(2)),
                   "prompt_n": int(m.group(3))}
            continue
        m = RE_EVAL.search(line)
        if m and cur.get("task") == int(m.group(1)):
            cur.update({"eval_ms": float(m.group(2)), "predicted_n": int(m.group(3))})
            continue
        m = RE_ACC.search(line)
        if m and cur.get("task") == int(m.group(1)):
            cur.update({"accept": float(m.group(2)), "accepted": int(m.group(3)),
                        "generated": int(m.group(4))})
            blocks.append(cur)
            cur = {}
    return blocks


def windows(path):
    """task -> (req_before, req_after) from the drivers' windows.txt"""
    out, started = {}, {}
    if not os.path.exists(path):
        return out
    for line in open(path):
        parts = line.split()
        if len(parts) < 2:
            continue
        task, kind = parts[0], parts[1]
        kv = dict(p.split("=", 1) for p in parts[2:] if "=" in p)
        if kind == "START":
            started[task] = int(kv["req_before"])
        elif kind == "END" and task in started:
            out[task] = (started[task], int(kv["req_after"]))
    return out


def summarize(blocks):
    pn = sum(b["prompt_n"] for b in blocks)
    pm = sum(b["prompt_ms"] for b in blocks)
    dn = sum(b.get("predicted_n", 0) for b in blocks)
    dm = sum(b.get("eval_ms", 0) for b in blocks)
    acc = sum(b.get("accepted", 0) for b in blocks)
    gen = sum(b.get("generated", 0) for b in blocks)
    return {
        "requests": len(blocks),
        "prompt_tok": pn,
        "prefill_s": pm / 1000.0,
        "fill_tok_s": (pn / pm * 1000.0) if pm else None,
        "completion_tok": dn,
        "decode_s": dm / 1000.0,
        "decode_tok_s": (dn / dm * 1000.0) if dm else None,
        "accepted": acc,
        "generated": gen,
        "accept_pct": (100.0 * acc / gen) if gen else None,
    }


if __name__ == "__main__":
    blocks = parse(os.path.join(LOGDIR, "timings_raw.txt"))
    W = windows(os.path.join(LOGDIR, "windows.txt"))
    print(f"total finished requests on the server: {len(blocks)}\n")
    print(f"{'idx':>3} {'task':>5} {'prompt_n':>9} {'pred_n':>7} {'fill tok/s':>11} {'dec tok/s':>10} {'acc':>6} {'gen':>5}")
    for i, b in enumerate(blocks):
        fill = b["prompt_n"] / b["prompt_ms"] * 1000 if b.get("prompt_ms") else 0
        dec = b.get("predicted_n", 0) / b["eval_ms"] * 1000 if b.get("eval_ms") else 0
        print(f"{i:>3} {b['task']:>5} {b['prompt_n']:>9} {b.get('predicted_n',0):>7} "
              f"{fill:>11.1f} {dec:>10.1f} {b.get('accepted',0):>6} {b.get('generated',0):>5}")
    print()
    for task, (lo, hi) in W.items():
        blk = blocks[lo:hi]
        s = summarize(blk)
        print(f"{task:16} req[{lo}:{hi}] -> {json.dumps(s)}")
