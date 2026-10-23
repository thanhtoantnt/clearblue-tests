#!/usr/bin/env python3
"""Gate for LockLeak::isIrrelevantNode treating a lock argument as irrelevant.

An unfixed analyzer reports maybe_local and misses maybe. A fixed analyzer
reports both, and does not report ok.

Usage: check_ll_arg_type_filter.py <fermat-check> [old.bc]
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NEED = ("maybe", "maybe_local")
MUST_NOT = ("ok",)


def funcs(report):
    found = set()
    for bug_type in report.get("BugTypes") or []:
        for item in bug_type.get("Reports") or []:
            for step in item.get("DiagSteps") or []:
                name = step.get("FuncName") or ""
                if name:
                    found.add(name)
    return found


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit("usage: check_ll_arg_type_filter.py <fermat-check> [old.bc]")
    binary = sys.argv[1]
    bitcode = (
        Path(sys.argv[2]) if len(sys.argv) == 3
        else ROOT / "bc/ll-arg-type-filter/old.bc"
    )
    scratch = Path.home() / "tmp"
    scratch.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="ll-arg-", dir=scratch) as tmp:
        report_path = Path(tmp) / "report.json"
        proc = subprocess.run(
            [
                binary,
                "--ps-ll",
                "-nworkers=1",
                "--hide-progress-bar",
                str(bitcode),
                "-report=%s" % report_path,
                "-omit-no-dbginfo",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=120,
        )
        if proc.returncode != 0 or not report_path.exists():
            sys.exit(
                "fermat-check failed (rc=%d):\n%s"
                % (proc.returncode, proc.stdout.decode(errors="replace"))
            )
        report = json.loads(report_path.read_text())

    found = funcs(report)
    missing = [n for n in NEED if n not in found]
    invented = [n for n in MUST_NOT if n in found]
    if missing or invented:
        print(
            "FAIL: missing %s; unexpected %s; reported %s"
            % (", ".join(missing) or "-", ", ".join(invented) or "-", sorted(found))
        )
        return 1
    print("PASS: %s reported; %s absent" % (", ".join(NEED), ", ".join(MUST_NOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
