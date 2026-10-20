#!/usr/bin/env python3
"""Compare an incremental report with a scratch report inside the work set.

Incremental checks the dirty cone, not the whole module. A bug is in the cone
when any diagnostic step's FuncKey is in the work-set file. Missing means
scratch found it in the cone and incremental did not. Invented means
incremental reported a trace scratch did not report at all.

Exit 0 on agreement, 1 on a mismatch, 2 on a bad input.
"""

import json
import sys


def bugs(path):
    report = json.load(open(path))
    out = []
    for bug_type in report.get("BugTypes") or []:
        name = bug_type.get("Name") or ""
        for item in bug_type.get("Reports") or []:
            steps = tuple(
                (step.get("FuncKey") or step.get("FuncName"), step.get("Line"))
                for step in (item.get("DiagSteps") or [])
            )
            out.append((name, steps))
    return out


def load_workset(path):
    names = set()
    for line in open(path):
        line = line.strip()
        if line and not line.startswith("#"):
            names.add(line)
    return names


def touches(steps, work):
    return any(func in work for func, _line in steps)


def main():
    if len(sys.argv) != 4:
        sys.stderr.write("usage: compare_cone_reports.py inc.json scratch.json workset.txt\n")
        return 2
    inc = bugs(sys.argv[1])
    scratch = bugs(sys.argv[2])
    work = load_workset(sys.argv[3])
    cone = [bug for bug in scratch if touches(bug[1], work)]
    invented = set(inc) - set(scratch)
    missing = set(cone) - set(inc)
    print(
        "inc=%d scratch=%d cone=%d invented=%d missing=%d workset=%d"
        % (len(inc), len(scratch), len(set(cone)), len(invented), len(missing), len(work))
    )
    for bug in sorted(invented)[:8]:
        print("INV", bug[0], bug[1][:6])
    for bug in sorted(missing)[:8]:
        print("MISS", bug[0], bug[1][:6])
    return 1 if invented or missing else 0


if __name__ == "__main__":
    sys.exit(main())
