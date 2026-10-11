#!/usr/bin/env python3
"""T2 rerun: N cold-start samples + grading + performance collection.

Cold start per sample: between samples the candidate container is restarted so
the prompt cache is empty and each sample is a genuine cold prefill (the earlier
r2/r3 samples hit the cache with a 4-token prompt, which is weaker evidence).

Grading is the canonical one - verbatim from the skill - and is NOT adjusted.
The only extra thing printed is WHY a failure failed.
"""
import base64, json, os, re, subprocess, sys, time, urllib.request
from html.parser import HTMLParser
import xml.etree.ElementTree as ET

R4 = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "CURRENT_R4")).read().strip()
LOGDIR = os.path.join(R4, "logs")
BASE = "http://192.0.2.101:18082"
MODEL = "/models/Qwen3.8-27B-Q4_K_M.gguf"
ONGPU = "<workspace>/scripts/on-gpu.sh"
PROMPT = json.load(open(os.path.join(LOGDIR, "prompts.json")))["t2_svg"]


def strip_fence(c):
    """Canonical fence stripper, verbatim from the backend-test-suite skill."""
    m = re.match(r"\s*```[a-zA-Z0-9]*\s*\n(.*?)\n?\s*```\s*$", c, re.S)
    return (m.group(1) if m else c).strip()


def call(prompt):
    payload = {
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 32768,
        "stream": True,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    req = urllib.request.Request(BASE + "/v1/chat/completions",
                                 data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.time(); t_first = None; parts = []; finish = None
    with urllib.request.urlopen(req, timeout=3600) as r:
        for line in r:
            s = line.decode("utf-8", "replace").strip()
            if not s.startswith("data:"):
                continue
            b = s[5:].strip()
            if b == "[DONE]":
                break
            try:
                ch = json.loads(b)
            except json.JSONDecodeError:
                continue
            for c in ch.get("choices") or []:
                d = (c.get("delta") or {}).get("content")
                if d:
                    if t_first is None:
                        t_first = time.time()
                    parts.append(d)
                if c.get("finish_reason"):
                    finish = c["finish_reason"]
    t_end = time.time()
    return {"content": "".join(parts), "finish": finish,
            "ttft_client": (t_first - t0) if t_first else None, "wall": t_end - t0}


def grade(content, finish):
    doc = strip_fence(content)
    checks = {"finish_reason == stop": finish == "stop"}
    try:
        root = ET.fromstring(doc)
        checks |= {"well-formed XML": True,
                   "single <svg> root": root.tag.split("}")[-1] == "svg",
                   "has viewBox": "viewBox" in root.attrib,
                   "ends at </svg>": doc.endswith("</svg>")}
    except ET.ParseError as e:
        checks |= {"well-formed XML": False, "parse_error": str(e)}
    return checks, doc


def restart_candidate():
    subprocess.run([ONGPU, "docker restart b70-dev-test-b11540"],
                   capture_output=True, text=True)
    for _ in range(60):
        try:
            with urllib.request.urlopen(BASE + "/v1/models", timeout=5):
                return True
        except Exception:
            time.sleep(4)
    return False


def req_count():
    p = subprocess.run([ONGPU, 'docker logs b70-dev-test-b11540 2>&1 | grep -c "draft acceptance"'],
                       capture_output=True, text=True)
    return int((p.stdout.strip().splitlines() or ["0"])[-1] or 0)


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    results = []
    for i in range(1, n + 1):
        name = f"t2_cold{i}"
        print(f"\n===== sample {i}/{n} ({name}) =====")
        before = req_count()
        cold = restart_candidate()
        if not cold:
            print("  !! candidate did not come back")
            break
        time.sleep(3)
        print(f"  cold start confirmed (restart ok); req_before={before}")
        t = call(PROMPT)
        after = req_count()
        checks, doc = grade(t["content"], t["finish"])
        passed = all(v for k, v in checks.items() if k != "parse_error")
        trailing = (len(t["content"]) - t["content"].find("</svg>") - 6) if "</svg>" in t["content"] else None
        rec = {"sample": name, "req_before": before, "req_after": after,
               "finish": t["finish"], "ttft_client_s": round(t["ttft_client"], 3) if t["ttft_client"] else None,
               "wall_s": round(t["wall"], 1), "chars": len(t["content"]),
               "fenced": t["content"].lstrip().startswith("```"),
               "chars_after_svg_close": trailing, "checks": checks, "verdict": "PASS" if passed else "FAIL"}
        results.append(rec)
        json.dump(t["content"], open(os.path.join(LOGDIR, f"{name}_raw.txt"), "w"))
        open(os.path.join(LOGDIR, f"{name}.svg"), "w").write(doc)
        print(f"  finish={t['finish']} verdict={'PASS' if passed else 'FAIL'}"
              f"  chars={len(t['content'])}  after </svg>={trailing}"
              f"  fenced={rec['fenced']}  ttft={rec['ttft_client_s']}s wall={rec['wall_s']}s")
        for k, v in checks.items():
            if k != "parse_error":
                print(f"    {'OK  ' if v else 'FAIL'} {k}")
            elif not v:
                print(f"    (parse error: {v})")
    json.dump(results, open(os.path.join(LOGDIR, "t2_rerun_results.json"), "w"), indent=2)
    print("\n===== summary =====")
    p = sum(1 for r in results if r["verdict"] == "PASS")
    print(f"  PASS {p}/{len(results)}   FAIL {len(results)-p}/{len(results)}")
    for r in results:
        print(f"  {r['sample']:10} {r['verdict']:4}  after </svg>={r['chars_after_svg_close']}  wall={r['wall_s']}s")


if __name__ == "__main__":
    main()
