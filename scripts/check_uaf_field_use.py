#!/usr/bin/env python3
"""Require all eight use-after-free functions in bc/uaf-field-external-use
to be reported.

Gate for the UseAfterFree::isSrcSinkNotAlias fix (FermatAnalyzer): an
unfixed analyzer misses the two field-derived external-call uses
(f_field, m2_arg0_gep) while reporting the byte-identical malloc-derived
shapes; a fixed analyzer reports all eight.

Usage: check_uaf_field_use.py <fermat-check> [old.bc]
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Every function in uaf_field_use.c is a genuine UAF.
NEED = (
    "f_field",          # field -> free -> strlen(p):        missed when unfixed
    "m2_arg0_gep",      # field -> free -> snprintf(x->buf): missed when unfixed
    "f_plain",          # malloc -> free -> strlen(p)
    "f_field_deref",    # field -> free -> p[0]
    "m1_arg0_plain",    # field -> free -> snprintf(out, ...)
    "m3_malloc_gep",    # malloc -> free -> snprintf(x->buf, ...)
    "u1_malloc",        # malloc -> free -> memset(p, ...)
    "u2_field",         # field  -> free -> memset(p, ...)
)


def funcs(report):
    found = set()
    for bug_type in report.get("BugTypes") or []:
        for item in bug_type.get("Reports") or []:
            for step in item.get("DiagSteps") or []:
                name = step.get("FuncName") or step.get("FuncKey") or ""
                if name in NEED:
                    found.add(name)
    return found


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit("usage: check_uaf_field_use.py <fermat-check> [old.bc]")
    binary = sys.argv[1]
    bitcode = (
        Path(sys.argv[2]) if len(sys.argv) == 3
        else ROOT / "bc/uaf-field-external-use/old.bc"
    )
    scratch = Path.home() / "tmp"
    scratch.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="uaf-field-use-", dir=scratch) as tmp:
        report_path = Path(tmp) / "report.json"
        proc = subprocess.run(
            [
                binary,
                "--ps-uaf",
                "-nworkers=1",
                "--hide-progress-bar",
                str(bitcode),
                "-report=%s" % report_path,
                "-omit-no-dbginfo",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=600,
        )
        if proc.returncode != 0 or not report_path.exists():
            sys.exit("fermat-check failed (rc=%d):\n%s" % (proc.returncode, proc.stdout.decode(errors="replace")))
        report = json.loads(report_path.read_text())

    found = funcs(report)
    missing = [n for n in NEED if n not in found]
    if missing:
        print("FAIL: %d/%d expected UAF functions reported; missing: %s" %
              (len(found), len(NEED), ", ".join(missing)))
        print("     (unfixed UseAfterFree::isSrcSinkNotAlias misses the"
              " field-derived external-call uses)")
        return 1
    print("PASS: all %d UAF functions reported" % len(NEED))
    return 0


if __name__ == "__main__":
    sys.exit(main())
