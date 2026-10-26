#!/usr/bin/env python3
"""Real-bitcode controls for the local-field release fix.

darknet's layer constructors store calloc results into a local and return
the struct through an sret argument. read_tree copies that local out with
llvm.memcpy. Neither is a leak. An unfixed analyzer also stays quiet here,
because every field store was a sink; the fixed analyzer must stay quiet
too, or the new exception is too wide.

Usage: check_local_field_suite.py <fermat-check> [darknet.bc]
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LLVM_EXTRACT = "/usr/lib/llvm-15/bin/llvm-extract"
QUIET = ("make_activation_layer", "copy_image", "read_tree")


def bugs(binary, bitcode, tmp, tag):
    report = Path(tmp) / ("%s.json" % tag)
    proc = subprocess.run(
        [
            binary,
            "--ps-ml",
            "-nworkers=1",
            "--hide-progress-bar",
            "-omit-no-dbginfo",
            str(bitcode),
            "-report=%s" % report,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    if proc.returncode != 0 or not report.exists():
        sys.exit(
            "%s failed (rc=%d):\n%s"
            % (tag, proc.returncode, proc.stdout.decode(errors="replace"))
        )
    data = json.loads(report.read_text())
    found = set()
    for bug_type in data.get("BugTypes") or []:
        for item in bug_type.get("Reports") or []:
            for step in item.get("DiagSteps") or []:
                name = step.get("FuncName") or ""
                if name:
                    found.add(name)
    return found, data.get("TotalBugs")


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit("usage: check_local_field_suite.py <fermat-check> [darknet.bc]")
    binary = sys.argv[1]
    bitcode = (
        Path(sys.argv[2]) if len(sys.argv) == 3 else ROOT / "bc/darknet/old.bc"
    )
    scratch = Path.home() / "tmp"
    scratch.mkdir(exist_ok=True)
    failed = []
    with tempfile.TemporaryDirectory(prefix="local-field-suite-", dir=scratch) as tmp:
        tmp = Path(tmp)
        for name in QUIET:
            extracted = tmp / ("%s.bc" % name)
            proc = subprocess.run(
                [LLVM_EXTRACT, "--func=%s" % name, "-o", str(extracted), str(bitcode)],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
            )
            if proc.returncode != 0:
                sys.exit(
                    "llvm-extract %s failed:\n%s"
                    % (name, proc.stdout.decode(errors="replace"))
                )
            found, total = bugs(binary, extracted, tmp, name)
            print("%s total=%s funcs=%s" % (name, total, sorted(found)))
            if name in found or (total not in (0, None) and total != 0):
                failed.append(name)
    if failed:
        print("FAIL: reported a transferred local field: %s" % ", ".join(failed))
        return 1
    print("PASS: darknet return/copy of a local field is not a leak")
    return 0


if __name__ == "__main__":
    sys.exit(main())
