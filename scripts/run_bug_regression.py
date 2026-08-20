#!/usr/bin/env python3
"""Run fermat-check on bc/*/old.bc and compare against bug_regression/*/expected.json.

Like FermatAnalyzerRegressionTest, but for full-project baselines from this bench:

  export CBC=/path/to/fermat-check
  python3 scripts/run_bug_regression.py
  python3 scripts/run_bug_regression.py --only libyaml,libexpat
  python3 scripts/run_bug_regression.py --cbc /other/fermat-check --jobs 4

Pass criteria (match_mode=by_sink):
  every expected (type, basename(file), line) must appear in the new report.
Extra findings are reported as WARN, not FAIL (analyzer may grow precision).
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

NAME_TO_TAG = {
    "Null Pointer Dereference": "NPD",
    "Use After Free": "UAF",
    "Memory Leak": "ML",
    "Invalid Use of Stack Address": "IUSA",
    "Use of Uninitialized Variable": "UUV",
}


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def extract_sinks(report: dict) -> list[dict]:
    src = report.get("SrcFiles") or []
    out = []
    for bt in report.get("BugTypes", []):
        name = bt.get("Name") or bt.get("BugType")
        tag = NAME_TO_TAG.get(name, name)
        for item in bt.get("Reports", []):
            if item.get("Valid") is False:
                continue
            sink = None
            for st in item.get("DiagSteps") or []:
                if st.get("Line") is not None:
                    sink = st
            if sink is None:
                continue
            fi = sink.get("File")
            fpath = src[fi] if isinstance(fi, int) and 0 <= fi < len(src) else str(fi)
            out.append(
                {
                    "type": tag,
                    "file": os.path.basename(fpath),
                    "line": int(sink.get("Line")),
                    "func": sink.get("FuncName") or sink.get("FuncKey") or "",
                }
            )
    return out


def sink_key(f: dict) -> tuple:
    return (f["type"], f["file"], int(f["line"]))


def compare(expected: dict, actual_sinks: list[dict]) -> dict:
    exp = [sink_key(f) for f in expected.get("findings", [])]
    act = [sink_key(f) for f in actual_sinks]
    exp_c = Counter(exp)
    act_c = Counter(act)

    missing = []
    for k, n in exp_c.items():
        if act_c[k] < n:
            missing.append({"key": k, "expected": n, "found": act_c[k]})

    extra = []
    for k, n in act_c.items():
        if n > exp_c[k]:
            extra.append({"key": k, "expected": exp_c[k], "found": n})

    counts_exp = expected.get("counts") or {}
    counts_act: dict[str, int] = defaultdict(int)
    for s in actual_sinks:
        counts_act[s["type"]] += 1

    ok = not missing
    return {
        "ok": ok,
        "expected_total": len(exp),
        "actual_total": len(act),
        "missing": missing,
        "extra": extra,
        "counts_expected": counts_exp,
        "counts_actual": dict(sorted(counts_act.items())),
    }


def run_case(
    cbc: Path,
    case_dir: Path,
    out_dir: Path,
    nworkers: int | None,
) -> dict:
    expected = json.loads((case_dir / "expected.json").read_text())
    proj = expected["project"]
    bc = (case_dir / expected["input_bc"]).resolve()
    if not bc.is_file():
        return {"project": proj, "ok": False, "error": f"missing bc: {bc}"}

    case_out = out_dir / proj
    case_out.mkdir(parents=True, exist_ok=True)
    report_path = case_out / "report.json"
    log_path = case_out / "run.log"

    nw = nworkers if nworkers is not None else int(expected.get("nworkers", 8))
    checkers = expected.get("checkers", "-ps-npd").split()

    def resolve_arg(tok: str) -> str:
        # resolve -load-memory-spec=<rel> against the repo root so the
        # harness works from any cwd
        if tok.startswith("-load-memory-spec="):
            p = Path(tok.split("=", 1)[1])
            if not p.is_absolute():
                p = (repo_root() / p).resolve()
            return f"-load-memory-spec={p}"
        return tok

    cmd = [
        str(cbc),
        str(bc),
        *checkers,
        *[
            resolve_arg(t)
            for t in expected.get("extra_args", "").split()
        ],
        "-omit-no-dbginfo",
        f"-nworkers={nw}",
        f"-report={report_path}",
    ]

    t0 = time.time()
    with open(log_path, "w") as log:
        proc = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, text=True)
    wall = time.time() - t0

    result = {
        "project": proj,
        "cmd": cmd,
        "exit": proc.returncode,
        "wall_sec": round(wall, 2),
        "report": str(report_path),
        "log": str(log_path),
    }
    if proc.returncode != 0:
        result["ok"] = False
        result["error"] = f"fermat-check exit {proc.returncode}"
        return result
    if not report_path.is_file():
        result["ok"] = False
        result["error"] = "no report.json"
        return result

    report = json.loads(report_path.read_text())
    sinks = extract_sinks(report)
    cmp = compare(expected, sinks)
    result.update(cmp)
    (case_out / "compare.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--cbc",
        default=os.environ.get("CBC", ""),
        help="path to fermat-check (or env CBC)",
    )
    ap.add_argument("--only", default="", help="comma-separated project names")
    ap.add_argument("--jobs", type=int, default=1, help="parallel cases")
    ap.add_argument(
        "--nworkers",
        type=int,
        default=None,
        help="override -nworkers per fermat-check",
    )
    ap.add_argument(
        "--out",
        default="",
        help="output dir (default: results/bug_regression/<timestamp>)",
    )
    args = ap.parse_args()

    root = repo_root()
    suite_dir = root / "bug_regression"
    if not suite_dir.is_dir():
        print("missing bug_regression/", file=sys.stderr)
        return 2

    cbc = Path(args.cbc) if args.cbc else None
    if not cbc or not cbc.is_file():
        print("set --cbc or CBC to a fermat-check binary", file=sys.stderr)
        return 2

    only = {x.strip() for x in args.only.split(",") if x.strip()}
    cases = sorted(
        p
        for p in suite_dir.iterdir()
        if p.is_dir() and (p / "expected.json").is_file()
    )
    if only:
        cases = [p for p in cases if p.name in only]
    if not cases:
        print("no cases selected", file=sys.stderr)
        return 2

    if args.out:
        out_dir = Path(args.out)
    else:
        stamp = time.strftime("%Y%m%d-%H%M%S")
        out_dir = root / "results" / "bug_regression" / stamp
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"cbc     : {cbc}")
    print(f"cases   : {len(cases)} {[p.name for p in cases]}")
    print(f"out     : {out_dir}")
    print(f"jobs    : {args.jobs}")

    results = []
    t0 = time.time()
    if args.jobs <= 1:
        for case in cases:
            print(f"... {case.name}", flush=True)
            results.append(run_case(cbc, case, out_dir, args.nworkers))
            r = results[-1]
            status = "PASS" if r.get("ok") else "FAIL"
            print(
                f"  {status} {case.name} wall={r.get('wall_sec')}s "
                f"exp={r.get('expected_total')} act={r.get('actual_total')} "
                f"miss={len(r.get('missing') or [])}",
                flush=True,
            )
    else:
        with ThreadPoolExecutor(max_workers=args.jobs) as ex:
            futs = {
                ex.submit(run_case, cbc, case, out_dir, args.nworkers): case
                for case in cases
            }
            for fut in as_completed(futs):
                case = futs[fut]
                r = fut.result()
                results.append(r)
                status = "PASS" if r.get("ok") else "FAIL"
                print(
                    f"  {status} {case.name} wall={r.get('wall_sec')}s "
                    f"exp={r.get('expected_total')} act={r.get('actual_total')} "
                    f"miss={len(r.get('missing') or [])}",
                    flush=True,
                )

    results.sort(key=lambda r: r.get("project", ""))
    wall = time.time() - t0
    n_pass = sum(1 for r in results if r.get("ok"))
    n_fail = len(results) - n_pass
    summary = {
        "cbc": str(cbc),
        "wall_sec": round(wall, 1),
        "pass": n_pass,
        "fail": n_fail,
        "total": len(results),
        "results": results,
    }
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")

    print("-" * 72)
    print(f"PASS {n_pass}/{len(results)}  FAIL {n_fail}  wall {wall:.1f}s")
    if n_fail:
        print("failed:")
        for r in results:
            if not r.get("ok"):
                print(
                    f"  - {r.get('project')}: {r.get('error') or 'missing sinks'} "
                    f"missing={len(r.get('missing') or [])}"
                )
                for m in (r.get("missing") or [])[:8]:
                    print(f"      {m}")
    print(f"summary: {out_dir / 'summary.json'}")
    return 0 if n_fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
