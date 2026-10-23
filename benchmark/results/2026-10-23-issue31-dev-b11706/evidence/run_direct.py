#!/usr/bin/env python3
"""Direct-task runner for the issue #29 B70 candidate.

Request fields are restricted to the two the suite permits:
  - chat_template_kwargs {"enable_thinking": false}  (thinking off, task protocol)
  - max_tokens 32768
plus stream:true for T1/T2 (transport, needed for TTFT).
No sampling parameter is ever sent: temperature/top_p/top_k/min_p/penalties/ctx
all come from the backend as deployed.
"""
import base64
import json
import os
import sys
import time
import urllib.request

BASE = os.environ.get("BASE", "http://192.0.2.101:18082")
MODEL = os.environ.get("MODEL", "/models/Qwen3.8-27B-Q4_K_M.gguf")
RUN = os.environ.get("RUN", "<workspace>/test-issue31")
MAXTOK = 32768


def post(path, body, stream, timeout=3600):
    req = urllib.request.Request(
        BASE + path, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"})
    return urllib.request.urlopen(req, timeout=timeout)


def run_text(task, prompt, stream):
    body = {
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": MAXTOK,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    if stream:
        body["stream"] = True

    t0 = time.time()
    content, timings, usage, finish = [], None, None, None
    ttft = None
    if stream:
        with post("/v1/chat/completions", body, True) as r:
            for raw in r:
                line = raw.decode("utf-8", "replace").strip()
                if not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    break
                try:
                    d = json.loads(data)
                except Exception:
                    continue
                if d.get("timings"):
                    timings = d["timings"]
                if d.get("usage"):
                    usage = d["usage"]
                for ch in d.get("choices") or []:
                    delta = (ch.get("delta") or {}).get("content")
                    if delta:
                        if ttft is None:
                            ttft = time.time() - t0
                        content.append(delta)
                    if ch.get("finish_reason"):
                        finish = ch["finish_reason"]
    else:
        with post("/v1/chat/completions", body, False) as r:
            d = json.loads(r.read().decode("utf-8", "replace"))
        ttft = time.time() - t0
        ch = d["choices"][0]
        finish = ch.get("finish_reason")
        c = ch["message"].get("content")
        if c:
            content.append(c)
        timings = d.get("timings")
        usage = d.get("usage")
    wall = time.time() - t0

    text = "".join(content)
    res = {
        "task": task, "wall_s": round(wall, 3),
        "ttft_s": round(ttft, 3) if ttft else None,
        "finish_reason": finish, "usage": usage, "timings": timings,
        "reasoning_present": None, "content_chars": len(text),
    }
    os.makedirs(f"{RUN}/results", exist_ok=True)
    ext = "html" if task == "t1" else ("svg" if task == "t2" else "txt")
    with open(f"{RUN}/results/{task}_output.{ext}", "w") as f:
        f.write(text)
    with open(f"{RUN}/results/{task}_result.json", "w") as f:
        json.dump(res, f, indent=1)
    print(json.dumps(res, indent=1)[:1200])
    return res


def run_image(task, prompt, imgpath, fmt):
    b64 = base64.b64encode(open(imgpath, "rb").read()).decode()
    body = {
        "model": MODEL,
        "messages": [{"role": "user", "content": [
            {"type": "text", "text": prompt},
            {"type": "image_url", "image_url": {"url": f"data:image/{fmt};base64,{b64}"}},
        ]}],
        "max_tokens": MAXTOK,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    t0 = time.time()
    with post("/v1/chat/completions", body, False) as r:
        d = json.loads(r.read().decode("utf-8", "replace"))
    ttft = time.time() - t0
    ch = d["choices"][0]
    text = ch["message"].get("content") or ""
    res = {
        "task": task, "ttft_s": round(ttft, 3),
        "finish_reason": ch.get("finish_reason"),
        "usage": d.get("usage"), "timings": d.get("timings"),
        "content_chars": len(text),
    }
    with open(f"{RUN}/results/{task}_output.txt", "w") as f:
        f.write(text)
    with open(f"{RUN}/results/{task}_result.json", "w") as f:
        json.dump(res, f, indent=1)
    print(json.dumps(res, indent=1)[:1200])
    return res


if __name__ == "__main__":
    which = sys.argv[1]
    P = json.load(open(f"{RUN}/logs/prompts.json"))
    if which == "t1":
        run_text("t1", P["t1_html"], True)
    elif which == "t2":
        run_text("t2", P["t2_svg"], True)
    else:
        v = which.lower()
        fmt = "png" if v == "v2" else "jpeg"
        ext = "png" if v == "v2" else "jpg"
        run_image(v, P[v],
                  f"<dsh-skills>/backend-test-suite/assets/"
                  + {"v1": "game_screenshot_Lila.jpg",
                     "v2": "motherboard_layout.png",
                     "v3": "tire_25570R18.jpg"}[v], fmt)
