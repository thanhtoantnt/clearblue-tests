#!/usr/bin/env python3
"""Require later loads of a freed cell to be reported, and the killed /
overlaid shapes not to be.

An unfixed analyzer misses every name in NEED (two loads of one cell, or a
wrapper that frees the pointer itself). A fixed analyzer reports all of
them and none of ABSENT.

Usage: check_uaf_reload_same_cell.py <fermat-check> [old.bc]
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NEED = (
    "reload_field",
    "reload_strlen",
    "double_reload",
    "use_before_null",
    "wrap_reload_ptr",
    "branch_partial",
    "branch_else_use",
    "branch_sibling",
    "early_return_store",
    "store_back_same",
    "callee_noop",
    "callee_restore",
    "index_same",
    "use_reload_store",
    "use_store_select",
    "index_ptr_stride",
)
ABSENT = (
    "killed_store",
    "killed_memset",
    "other_index",
    "overlay_fp",
    "branch_both_kill",
    "snapshot_then_store",
    "callee_fresh",
    "index_other",
    "probe_c_const_scale",
    "probe_var_scale",
)


def funcs(report):
    found = set()
    for bug_type in report.get("BugTypes") or []:
        for item in bug_type.get("Reports") or []:
            for step in item.get("DiagSteps") or []:
                name = step.get("FuncName") or step.get("FuncKey") or ""
                if name:
                    found.add(name)
    return found


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit("usage: check_uaf_reload_same_cell.py <fermat-check> [old.bc]")
    binary = sys.argv[1]
    bitcode = (
        Path(sys.argv[2])
        if len(sys.argv) == 3
        else ROOT / "bc/uaf-reload-same-cell/old.bc"
    )
    scratch = Path.home() / "tmp"
    scratch.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="uaf-reload-", dir=scratch) as tmp:
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
            sys.exit(
                "fermat-check failed (rc=%d):\n%s"
                % (proc.returncode, proc.stdout.decode(errors="replace"))
            )
        found = funcs(json.loads(report_path.read_text()))

    missing = [n for n in NEED if n not in found]
    spurious = [n for n in ABSENT if n in found]
    if missing or spurious:
        print(
            "FAIL: missing %s; spurious %s; found %s"
            % (", ".join(missing) or "-", ", ".join(spurious) or "-", sorted(found))
        )
        return 1
    print("PASS: %d reload UAFs reported, %d non-bugs absent" % (len(NEED), len(ABSENT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
