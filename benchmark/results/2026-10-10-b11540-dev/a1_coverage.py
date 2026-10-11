#!/usr/bin/env python3
"""A1 review-coverage observation (reported, never gating).

Counts the files the agent actually READ against the files present in the clone
it made, from the session record -- not from the report's own claims.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RUNDIR = open(os.path.join(HERE, "CURRENT_RUNDIR")).read().strip()
LOGDIR = os.path.join(RUNDIR, "logs")
SESS = os.path.join(LOGDIR, "a1_security.session.jsonl")


def find_repo():
    ws = os.path.join(RUNDIR, "dsh-home", "workspace")
    for dirpath, dirnames, _ in os.walk(ws):
        for d in list(dirnames):
            if d in ("mqtt2ha",):
                return os.path.join(dirpath, d)
    return None


def main():
    root = find_repo()
    if not root:
        print("no clone found under the harness workspace -- A1 did not acquire the repo")
        return
    ev = []
    for line in open(SESS, errors="replace"):
        line = line.strip()
        if line:
            try:
                ev.append(json.loads(line))
            except json.JSONDecodeError:
                pass

    def args(d):
        a = d.get("arguments")
        if isinstance(a, str):
            try:
                a = json.loads(a)
            except Exception:
                a = {}
        return a if isinstance(a, dict) else {}

    touched = set()
    reads = 0
    for e in ev:
        if e.get("type") != "tool/call":
            continue
        d = e.get("data") or {}
        name, a = d.get("name"), args(d)
        if name == "read":
            fp = str(a.get("file_path", ""))
            if "/mqtt2ha/" in fp:
                touched.add(fp.split("/mqtt2ha/", 1)[1])
                reads += 1
        elif name in ("bash", "grep", "glob"):
            for m in re.findall(r"mqtt2ha/([A-Za-z0-9._/+-]+)", str(a.get("command", "")) + str(a.get("path", ""))):
                tok = m.rstrip(".,;)")
                if "." in os.path.basename(tok):
                    touched.add(tok)

    inv = {os.path.relpath(os.path.join(dp, f), root)
           for dp, _, fs in os.walk(root) if "/.git" not in dp for f in fs}
    inv -= {".git"}
    hit = touched & inv
    print(f"clone root                : {root}")
    print(f"inventory (files, no .git): {len(inv)}")
    print(f"read calls (file_path)    : {reads}")
    print(f"files touched / inventory : {len(hit)} / {len(inv)}  ({len(hit)/len(inv):.0%})")
    missed = sorted(inv - touched)
    print(f"missed ({len(missed)}): {', '.join(missed)}")
    tests = [m for m in missed if m.endswith("_test.go")]
    print(f"notable                   : {len(tests)} _test.go files skipped" if tests
          else "notable                   : no _test.go files in the clone or none skipped")


if __name__ == "__main__":
    main()
