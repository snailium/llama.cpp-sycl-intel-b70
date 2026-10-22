#!/usr/bin/env python3
"""Extract per-task metrics from llama-server `slot print_timing` records.

Usage: extract_metrics.py <full_log> <task> <logline_before> <logline_after>

The server runs with DEBUG_FLAG=-v, so every request emits:

    0.40.310.779 I slot print_timing: id  0 | task 0 | prompt eval time = 1087.47 ms / 17 tokens
    0.40.310.779 I slot print_timing: id  0 | task 0 |        eval time =  279.13 ms /  2 tokens
    0.40.310.780 I slot print_timing: id  0 | task 0 |       total time = 1366.60 ms / 19 tokens
    0.40.310.785 I slot print_timing: id  0 | task 0 | draft acceptance = 0.0 (0 accepted / 3 generated), mean len = 1.0

A request is a *block* of consecutive print_timing lines. For direct tasks the
response body also carries a `timings` block (authoritative, reported separately);
for agent tasks (A1-A3) the harness is the client and this log is the only source.

Reported, always:
  fill   = prompt_tokens / prompt_ms * 1000   (prefill tok/s; largest-prompt call)
  TTFT   = prompt_ms / 1000                   (server-side; excludes queueing)
  decode = eval_tokens / eval_ms * 1000       (summed over the window)
  accept = accepted / generated, with K
"""
import re, sys, json

RE_PROMPT = re.compile(r'prompt eval time\s*=\s*([0-9.]+) ms\s*/\s*(\d+) tokens')
RE_EVAL = re.compile(r'(?<!prompt )\beval time\s*=\s*([0-9.]+) ms\s*/\s*(\d+) tokens')
RE_DRAFT = re.compile(r'draft acceptance\s*=\s*([0-9.]+)\s*\(\s*(\d+) accepted\s*/\s*(\d+) generated\)')


def parse_blocks(lines):
    blocks, cur = [], None
    for ln in lines:
        if 'print_timing' not in ln:
            continue
        m = RE_PROMPT.search(ln)
        if m:  # a prompt-eval line starts a new block
            if cur:
                blocks.append(cur)
            cur = {"prompt_ms": float(m.group(1)), "prompt_n": int(m.group(2))}
            continue
        if cur is None:
            continue
        m = RE_EVAL.search(ln)
        if m and 'eval_ms' not in cur:
            cur["eval_ms"] = float(m.group(1)); cur["eval_n"] = int(m.group(2)); continue
        m = RE_DRAFT.search(ln)
        if m:
            cur.setdefault("accept", float(m.group(1)))
            cur["accepted"] = int(m.group(2)); cur["generated"] = int(m.group(3))
    if cur:
        blocks.append(cur)
    return [b for b in blocks if b.get("eval_n", 0) > 0]


def main():
    path, task, lo, hi = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
    win = []
    with open(path, errors='replace') as f:
        for i, ln in enumerate(f, 1):
            if i < lo:
                continue
            if i > hi:
                break
            if 'print_timing' in ln:
                win.append(ln)
    blocks = parse_blocks(win)
    if not blocks:
        print(json.dumps({"task": task, "requests": 0,
                          "note": "no print_timing records in window"}))
        return
    big = max(blocks, key=lambda b: b.get("prompt_n", 0))
    tot_eval = sum(b.get("eval_n", 0) for b in blocks)
    tot_eval_ms = sum(b.get("eval_ms", 0.0) for b in blocks)
    tot_gen = sum(b.get("generated", 0) for b in blocks)
    tot_acc = sum(b.get("accepted", 0) for b in blocks)
    res = {
        "task": task,
        "requests": len(blocks),
        "fill_tok_s": round(big["prompt_n"] / big["prompt_ms"] * 1000, 2) if big.get("prompt_ms") else None,
        "fill_prompt_n": big.get("prompt_n"),
        "ttft_s": round(big["prompt_ms"] / 1000, 3) if big.get("prompt_ms") else None,
        "decode_tok_s": round(tot_eval / tot_eval_ms * 1000, 2) if tot_eval_ms else None,
        "completion_tok": tot_eval,
        "draft_generated": tot_gen,
        "draft_accepted": tot_acc,
        "accept_pct": round(tot_acc / tot_gen * 100, 1) if tot_gen else None,
        "K": 3,
    }
    print(json.dumps(res, indent=1))


if __name__ == "__main__":
    main()
