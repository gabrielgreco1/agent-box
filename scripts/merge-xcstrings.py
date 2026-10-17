#!/usr/bin/env python3
"""Resolve a conflicted .xcstrings by unioning keys from ours (:2) and theirs (:3). Usage: merge-xcstrings.py <path>"""
import json, subprocess, sys
p = sys.argv[1]
ours = json.loads(subprocess.check_output(["git", "show", ":2:" + p]))
theirs = json.loads(subprocess.check_output(["git", "show", ":3:" + p]))
for k, v in theirs.get("strings", {}).items():
    ours["strings"].setdefault(k, v)
open(p, "w").write(json.dumps(ours, indent=2, ensure_ascii=False, sort_keys=True) + "\n")
subprocess.check_call(["git", "add", p])
