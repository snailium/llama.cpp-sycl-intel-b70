#!/usr/bin/env python3
"""Mechanical T1/T2 grading -- never from the model's description of its output.

Structure checks exactly as specified by the backend-test-suite skill.
"""
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from html.parser import HTMLParser

RUNDIR = open(os.path.join(os.path.dirname(__file__), "CURRENT_RUNDIR")).read().strip()
LOGDIR = os.path.join(RUNDIR, "logs")


def strip_fence(c):
    m = re.match(r"\s*```[a-zA-Z0-9]*\s*\n(.*?)\n?\s*```\s*$", c, re.S)
    return (m.group(1) if m else c).strip()


def grade(name, kind):
    d = json.load(open(os.path.join(LOGDIR, f"{name}_result.json")))
    ch = d["choices"][0]
    doc = strip_fence(ch["message"].get("content") or "")
    checks = {"finish_reason == stop": ch.get("finish_reason") == "stop"}
    if kind == "html":
        stack, bad = [], []

        class P(HTMLParser):
            VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input",
                    "link", "meta", "source", "track", "wbr"}

            def handle_starttag(self, t, a):
                if t not in self.VOID:
                    stack.append(t)

            def handle_endtag(self, t):
                if stack and stack[-1] == t:
                    stack.pop()
                else:
                    bad.append(t)

        P().feed(doc)
        checks |= {
            "parses / balanced": not bad and not stack,
            "html/head/body": all(f"<{t}" in doc for t in ("html", "head", "body")),
            "ends at </html>": doc.endswith("</html>"),
        }
    else:
        try:
            root = ET.fromstring(doc)
            checks |= {
                "well-formed XML": True,
                "single <svg> root": root.tag.split("}")[-1] == "svg",
                "has viewBox": "viewBox" in root.attrib,
                "ends at </svg>": doc.endswith("</svg>"),
            }
        except ET.ParseError as e:
            checks |= {"well-formed XML": False}
            print(f"  {name}: XML parse error: {e}")
    print(f"  {name}: {'PASS' if all(checks.values()) else 'FAIL'}")
    for k, v in checks.items():
        print(f"    {'OK  ' if v else 'FAIL'} {k}")
    # keep the markup as a document, fence stripped
    ext = "html" if kind == "html" else "svg"
    open(os.path.join(LOGDIR, f"{name}.{ext}"), "w").write(doc)
    return all(checks.values())


if __name__ == "__main__":
    ok1 = grade("t1_html", "html")
    ok2 = grade("t2_svg", "xml")
    sys.exit(0 if (ok1 and ok2) else 1)
