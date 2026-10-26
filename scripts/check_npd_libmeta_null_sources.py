#!/usr/bin/env python3
"""Gate: a "not found" NULL return is a null source.

getenv/strrchr/strpbrk/memmem/bsearch return NULL when nothing matches,
the same contract strchr already had in the analyzer's table. An unfixed
analyzer reports only strchr_baseline; a fixed one reports every
*_unchecked and no *_checked.

Usage: check_npd_libmeta_null_sources.py <fermat-check> [old.bc]
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NEED = (
    "getenv_unchecked",
    "strrchr_unchecked",
    "strpbrk_unchecked",
    "memmem_unchecked",
    "bsearch_unchecked",
    "strchr_baseline",
)
MUST_NOT = ("getenv_checked", "strrchr_checked")


def sink_funcs(report):
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
        sys.exit("usage: check_npd_libmeta_null_sources.py <fermat-check> [old.bc]")
    binary = sys.argv[1]
    bitcode = (
        Path(sys.argv[2]) if len(sys.argv) == 3
        else ROOT / "bc/npd-libmeta-null-sources/old.bc"
    )
    scratch = Path.home() / "tmp"
    scratch.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="npd-libmeta-", dir=scratch) as tmp:
        report_path = Path(tmp) / "report.json"
        proc = subprocess.run(
            [
                binary,
                "--ps-npd",
                "-nworkers=1",
                "--hide-progress-bar",
                "-omit-no-dbginfo",
                str(bitcode),
                "-report=%s" % report_path,
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

    found = sink_funcs(report)
    missing = [n for n in NEED if n not in found]
    invented = [n for n in MUST_NOT if n in found]
    if missing or invented:
        print(
            "FAIL: missing %s; unexpected %s; reported %s"
            % (", ".join(missing) or "-", ", ".join(invented) or "-", sorted(found))
        )
        return 1
    print("PASS: not-found NULL returns are null sources; checks stay quiet")
    return 0


if __name__ == "__main__":
    sys.exit(main())
