#!/usr/bin/env python3
"""Gate: a pointer stored into a local field that does not escape is a leak.

An unfixed analyzer treats every field store as a release, so leak_field
and leak_file are missed. A fixed analyzer reports those two and does not
report a store into a caller object, a free/fclose, or a handoff of the
local's address.

Usage: check_local_field_leak.py <fermat-check> [old.bc]
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NEED_ML = ("leak_field", "leak_calloc", "leak_nested")
NEED_FDL = ("leak_file", "leak_slot")
MUST_NOT = (
    "saved_field",
    "saved_file",
    "freed_field",
    "closed_file",
    "handoff_field",
    "make_field",
    "pass_by_value",
    "copy_out",
)


def funcs(report):
    found = set()
    for bug_type in report.get("BugTypes") or []:
        for item in bug_type.get("Reports") or []:
            for step in item.get("DiagSteps") or []:
                name = step.get("FuncName") or ""
                if name:
                    found.add(name)
    return found


def run(binary, bitcode, flag, tmp):
    report_path = Path(tmp) / (flag + ".json")
    proc = subprocess.run(
        [
            binary,
            flag,
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
            "fermat-check %s failed (rc=%d):\n%s"
            % (flag, proc.returncode, proc.stdout.decode(errors="replace"))
        )
    return json.loads(report_path.read_text())


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit("usage: check_local_field_leak.py <fermat-check> [old.bc]")
    binary = sys.argv[1]
    bitcode = (
        Path(sys.argv[2]) if len(sys.argv) == 3
        else ROOT / "bc/local-field-leak/old.bc"
    )
    scratch = Path.home() / "tmp"
    scratch.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="local-field-", dir=scratch) as tmp:
        ml = funcs(run(binary, bitcode, "--ps-ml", tmp))
        fdl = funcs(run(binary, bitcode, "--ps-fdl", tmp))
    missing = [n for n in NEED_ML if n not in ml]
    missing += [n for n in NEED_FDL if n not in fdl]
    invented = [n for n in MUST_NOT if n in ml or n in fdl]
    if missing or invented:
        print(
            "FAIL: missing %s; unexpected %s; ml %s; fdl %s"
            % (
                ", ".join(missing) or "-",
                ", ".join(invented) or "-",
                sorted(ml),
                sorted(fdl),
            )
        )
        return 1
    print("PASS: local-field leaks reported; return, handoff, and free stay quiet")
    return 0


if __name__ == "__main__":
    sys.exit(main())
