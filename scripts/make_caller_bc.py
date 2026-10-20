#!/usr/bin/env python3
"""Build a one-function-changed bitcode from a fermat-check report.

Picks the caller (last distinct function) of the first multi-function bug
and inserts a dead `add i32 0, 0` into that function. The callee body is
unchanged, so an incremental run must load its summary rather than recheck it.
"""

import json
import subprocess
import sys


def traces(path):
    report = json.load(open(path))
    out = []
    for bug_type in report.get("BugTypes") or []:
        name = bug_type.get("Name") or ""
        for item in bug_type.get("Reports") or []:
            funcs = []
            for step in item.get("DiagSteps") or []:
                func = step.get("FuncKey") or step.get("FuncName")
                if func and func not in funcs:
                    funcs.append(func)
            if len(funcs) >= 2:
                out.append((name, funcs))
    return out


def insert_probe(text, func):
    key = "@%s(" % func
    start = 0
    while True:
        at = text.find(key, start)
        if at < 0:
            return None
        line = text.rfind("\n", 0, at) + 1
        if text.startswith("define", line):
            brace = text.find("{", at)
            if brace < 0:
                return None
            nl = text.find("\n", brace)
            return text[: nl + 1] + "  %persist_probe = add i32 0, 0\n" + text[nl + 1 :]
        start = at + 1


def main():
    if len(sys.argv) != 6:
        sys.stderr.write(
            "usage: make_caller_bc.py report.json old.bc out.bc llvm-dis llvm-as\n"
        )
        return 2
    report, old_bc, out_bc, llvm_dis, llvm_as = sys.argv[1:]
    found = traces(report)
    if not found:
        sys.stderr.write("no multi-function bug in %s\n" % report)
        return 2
    text = subprocess.check_output([llvm_dis, "-o", "-", old_bc], text=True, errors="replace")
    chosen = None
    mutated = None
    for _name, funcs in found:
        mutated = insert_probe(text, funcs[-1])
        if mutated is not None:
            chosen = funcs[-1]
            break
    if mutated is None:
        sys.stderr.write("no bug caller had a define in %s\n" % old_bc)
        return 2
    ll = out_bc + ".ll"
    with open(ll, "w") as fh:
        fh.write(mutated)
    subprocess.check_call([llvm_as, "-o", out_bc, ll])
    sys.stdout.write(chosen + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
