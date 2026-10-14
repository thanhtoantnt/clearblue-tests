# fermat-check `-ps-stable` run — clearblue-tests `old.bc` (15 projects)

Run date: 2026-09-04. Analyzer: `fermat-check` `1.0-20260904-24de6326`
(FermatAnalyzer branch `toan-docs` = `main` @ `24de6326`), LLVM 15 build.

Command per project (see `/home/toan/tmp` scratch for logs; only reports kept here):

```
fermat-check -nworkers=8 -ps-stable -report=results-ps-stable/<proj>/bug_report.txt bc/<proj>/old.bc
```

Contents:

- `summary.tsv` — per-project bug counts parsed from the JSON reports
  (these are the **post-filter** numbers; the console summary at end of a run
  shows pre-filter counts and is higher, e.g. openssh 85 pre-filter vs 2 kept).
- `<proj>/bug_report.txt` — JSON bug report (file is JSON despite the name).
- `status.log` — exit code / wall seconds per project, in finish order.

All 15 runs exited 0. Wall time 54 s (libjpeg-turbo) … 37 min (unbound).
No race/deadlock adhoc checkers, per-PR bitcode not covered — baseline `old.bc` only.
