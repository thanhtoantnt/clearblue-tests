#!/usr/bin/env python3
"""Require both PR #180 review findings to be reported.

copy_freed: memcpy of a freed byte buffer.
use_after: void* wrapper frees msg->rr; the caller copies that field.

Usage: check_uaf_wrapper_memcpy.py <fermat-check> [old.bc]
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NEED = ("copy_freed", "use_after")


def funcs(report):
    found = set()
    for bug_type in report.get("BugTypes") or []:
        for item in bug_type.get("Reports") or []:
            for step in item.get("DiagSteps") or []:
                name = step.get("FuncName") or step.get("FuncKey") or ""
                for needle in NEED:
                    if needle in name:
                        found.add(needle)
    return found


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit("usage: check_uaf_wrapper_memcpy.py <fermat-check> [old.bc]")
    binary = sys.argv[1]
    bitcode = (
        Path(sys.argv[2]) if len(sys.argv) == 3 else ROOT / "bc/uaf-wrapper-memcpy/old.bc"
    )
    scratch = Path.home() / "tmp"
    scratch.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="uaf-pr180-", dir=scratch) as tmp:
        report_path = Path(tmp) / "report.json"
        proc = subprocess.run(
            [
                binary,
                "--ps-uaf",
                "-nworkers=1",
                "--hide-progress-bar",
                str(bitcode),
                "-report=%s" % report_path,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        if proc.returncode != 0:
            sys.exit("fermat-check exited %d\n%s" % (proc.returncode, proc.stdout[-2000:]))
        found = funcs(json.loads(report_path.read_text()))
    missing = [name for name in NEED if name not in found]
    if missing:
        sys.exit("missing UAF in %s; found %s" % (", ".join(missing), sorted(found)))
    print("ok %s" % ", ".join(NEED))


if __name__ == "__main__":
    main()
