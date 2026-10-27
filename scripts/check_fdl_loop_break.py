#!/usr/bin/env python3
"""Gate for the loop-break FDL false positive (issue #277).

not_a_leak must be absent. real_leak_on_break and
real_leak_on_normal_exit must both be reported: the infeasible
null-cursor trace is not the only way those leaks exist.
"""

import json
import sys

MUST_REPORT = {"real_leak_on_break", "real_leak_on_normal_exit"}
MUST_BE_ABSENT = {"not_a_leak"}


def funcs(report_path):
    found = set()
    with open(report_path, encoding="utf-8") as handle:
        report = json.load(handle)
    for bug_type in report.get("BugTypes") or []:
        for item in bug_type.get("Reports") or []:
            steps = item.get("DiagSteps") or []
            if steps and steps[0].get("FuncName"):
                found.add(steps[0]["FuncName"])
    return found


def main():
    if len(sys.argv) != 2:
        print("usage: check_fdl_loop_break.py <report.json>", file=sys.stderr)
        return 2
    found = funcs(sys.argv[1])
    missing = sorted(MUST_REPORT - found)
    invented = sorted(MUST_BE_ABSENT & found)
    if missing or invented:
        print(f"FAIL missing={missing} invented={invented} found={sorted(found)}")
        return 1
    print(f"PASS: {sorted(MUST_REPORT)} reported, {sorted(MUST_BE_ABSENT)} quiet")
    return 0


if __name__ == "__main__":
    sys.exit(main())
