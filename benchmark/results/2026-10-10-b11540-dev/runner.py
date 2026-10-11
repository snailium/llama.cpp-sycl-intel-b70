#!/usr/bin/env python3
"""Issue #29 B70 backend-suite runner.

Rules enforced here (see the backend-test-suite skill):
  * prompts are READ FROM prompts.json, which was extracted from the skill file
    at run time -- never transcribed into this script (Rule 5c)
  * only two request fields are ever sent besides the prompt and, for T1/T2,
    stream (transport):  chat_template_kwargs.enable_thinking=False  and
    max_tokens.  No sampling parameter is touched (Rule 1).
"""
import base64
import json
import os
import sys
import time
import urllib.request
import urllib.error

BASE = os.environ.get("B70_BASE", "http://192.0.2.101:18082")
MODEL = os.environ.get("B70_MODEL", "/models/Qwen3.8-27B-Q4_K_M.gguf")
RUNDIR = os.environ["RUNDIR"]
SKILL_ASSETS = "<dsh-skills>/backend-test-suite/assets"

PROMPTS = json.load(open(os.path.join(RUNDIR, "logs", "prompts.json")))
LOGDIR = os.path.join(RUNDIR, "logs")
os.makedirs(LOGDIR, exist_ok=True)


def _post(path, payload, timeout=7200):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    return req, timeout


def chat_stream(task, prompt):
    """Streaming completion: gives a real TTFT."""
    payload = {
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 32768,
        "stream": True,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    req, timeout = _post("/v1/chat/completions", payload)
    t0 = time.time()
    t_first = None
    content = []
    finish = None
    usage = None
    timings = None
    raw_path = os.path.join(LOGDIR, f"{task}_raw.jsonl")
    with open(raw_path, "w") as rawf, urllib.request.urlopen(req, timeout=timeout) as r:
        for line in r:
            s = line.decode("utf-8", "replace").strip()
            if not s.startswith("data:"):
                continue
            body = s[5:].strip()
            if body == "[DONE]":
                break
            try:
                ch = json.loads(body)
            except json.JSONDecodeError:
                continue
            rawf.write(json.dumps(ch, ensure_ascii=False) + "\n")
            if ch.get("usage"):
                usage = ch["usage"]
            if ch.get("timings"):
                timings = ch["timings"]
            for c in ch.get("choices") or []:
                delta = (c.get("delta") or {}).get("content")
                if delta:
                    if t_first is None:
                        t_first = time.time()
                    content.append(delta)
                if c.get("finish_reason"):
                    finish = c["finish_reason"]
    t_end = time.time()
    return {
        "task": task,
        "choices": [
            {"message": {"content": "".join(content)}, "finish_reason": finish}
        ],
        "usage": usage,
        "timings": timings,
        "client": {
            "t0": t0,
            "t_first": t_first,
            "t_end": t_end,
            "ttft_s": (t_first - t0) if t_first else None,
            "wall_s": t_end - t0,
        },
    }


def chat_image(task, prompt, image_path, fmt):
    payload = {
        "model": MODEL,
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": "data:image/%s;base64,%s"
                            % (
                                fmt,
                                base64.b64encode(open(image_path, "rb").read()).decode(),
                            )
                        },
                    },
                ],
            }
        ],
        "max_tokens": 32768,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    req, timeout = _post("/v1/chat/completions", payload)
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        body = {"error": e.read().decode()[:4000], "status": e.code}
    t_end = time.time()
    out = dict(body) if isinstance(body, dict) else {"body": body}
    out["task"] = task
    out["client"] = {"t0": t0, "t_end": t_end, "wall_s": t_end - t0}
    return out


def main():
    what = sys.argv[1]
    outname = sys.argv[2] if len(sys.argv) > 2 else what
    if what in ("t1_html", "t2_svg"):
        res = chat_stream(outname, PROMPTS[what])
    elif what in ("v1", "v2", "v3"):
        assets = {
            "v1": ("game_screenshot_Lila.jpg", "jpeg"),
            "v2": ("motherboard_layout.png", "png"),
            "v3": ("tire_25570R18.jpg", "jpeg"),
        }
        fn, fmt = assets[what]
        res = chat_image(what, PROMPTS[what], os.path.join(SKILL_ASSETS, fn), fmt)
    else:
        raise SystemExit(f"unknown task {what}")

    outp = os.path.join(LOGDIR, f"{outname}_result.json")
    json.dump(res, open(outp, "w"), ensure_ascii=False, indent=2)
    c = res.get("client", {})
    u = res.get("usage") or {}
    print(
        f"{what}: finish={ (res.get('choices') or [{}])[0].get('finish_reason') } "
        f"prompt_tok={u.get('prompt_tokens')} completion_tok={u.get('completion_tokens')} "
        f"ttft={c.get('ttft_s')} wall={c.get('wall_s')} -> {outp}"
    )


if __name__ == "__main__":
    main()
