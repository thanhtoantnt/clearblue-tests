#!/usr/bin/env python3
"""Fail when the JSON statistic name is not the pre-pass name.

Usage: check_robin_map_stat_name.py <fermat-check> [old.bc]
"""
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NEEDLE = "insert_impl_with_hash"


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit("usage: check_robin_map_stat_name.py <fermat-check> [old.bc]")
    binary = sys.argv[1]
    bitcode = Path(sys.argv[2]) if len(sys.argv) == 3 else ROOT / "bc/robin-map/old.bc"
    scratch = Path.home() / "tmp"
    scratch.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="robin-map-stat-", dir=scratch) as tmp:
        report = Path(tmp) / "report.json"
        proc = subprocess.run(
            [binary, str(bitcode), "-report=%s" % report, "--hide-progress-bar"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        if proc.returncode != 0:
            sys.exit("fermat-check exited %d\n%s" % (proc.returncode, proc.stdout[-2000:]))
        match = re.search(
            r"Function With Most Instructions: (\d+) \(Function: (.+)\)",
            proc.stdout,
        )
        if not match:
            sys.exit("pre-pass statistic line missing")
        stdout_count, stdout_name = match.group(1), match.group(2)
        data = json.loads(report.read_text())
    json_name = data.get("FuncWithMostInst")
    json_count = str(data.get("MaxInstPerFunc"))
    if NEEDLE not in stdout_name:
        sys.exit("pre-pass max function is not %s: %s" % (NEEDLE, stdout_name[:160]))
    if json_name != stdout_name or json_count != stdout_count:
        sys.exit(
            "statistic name lost after aggregate-return demotion\n"
            "stdout: %s (%s)\njson:   %s (%s)"
            % (stdout_name[:160], stdout_count, str(json_name)[:160], json_count)
        )
    print("ok %s inst=%s" % (NEEDLE, stdout_count))


if __name__ == "__main__":
    main()
