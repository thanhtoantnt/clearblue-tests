#!/usr/bin/env python3
"""Summarize an A/B TSV (from ab_branches.sh) into main-vs-perf tables.

Usage: python3 scripts/ab_summarize.py /tmp/ab2.tsv
"""
import csv, sys, statistics
from collections import defaultdict

path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ab2.tsv"
store = defaultdict(dict)                                  # proj -> branch -> ms
inc = defaultdict(lambda: defaultdict(list))              # proj -> branch -> [ms]
with open(path) as f:
    for x in csv.DictReader(f, delimiter="\t"):
        if x["mode"] == "store":
            store[x["project"]][x["branch"]] = int(x["ms"])
        elif x["mode"] == "inc":
            inc[x["project"]][x["branch"]].append(int(x["ms"]))

projects = sorted(set(store) | set(inc))
med = lambda v: statistics.median(v) if v else 0

print("=" * 72)
print("STORE (one-time setup)")
print("=" * 72)
print(f"{'project':<14}{'main':>9}{'perf':>9}{'Δ':>9}")
print("-" * 41)
tm = tp = 0
for p in projects:
    m, pe = store[p].get("main", 0), store[p].get("perf", 0)
    tm, tp = tm + m, tp + pe
    d = pe - m
    pct = (d / m * 100) if m else 0
    print(f"{p:<14}{m//1000:>7}s{pe//1000:>7}s  {d/1000:+.0f}s ({pct:+.0f}%)")
print("-" * 41)
d = tp - tm
print(f"{'TOTAL':<14}{tm//1000:>7}s{tp//1000:>7}s  {d/1000:+.0f}s ({d/tm*100:+.1f}%)")

print("\n" + "=" * 72)
print("INCREMENTAL (per-PR median)")
print("=" * 72)
print(f"{'project':<14}{'prs':>4}{'main':>9}{'perf':>9}{'Δ':>9}{'Δ%':>8}")
print("-" * 53)
am = ap = []
for p in projects:
    ml, pl = inc[p]["main"], inc[p]["perf"]
    if not ml or not pl:
        continue
    mm, pm = med(ml), med(pl)
    am, ap = am + ml, ap + pl
    d = pm - mm
    pct = (d / mm * 100) if mm else 0
    tag = "✓" if pm < mm else ("=" if pm == mm else "✗")
    print(f"{p:<14}{min(len(ml),len(pl)):>4}{mm//1000:>7}s{pm//1000:>7}s"
          f"  {d/1000:+.0f}s{pct:+7.0f}% {tag}")
print("-" * 53)
mm, pm = med(am), med(ap)
wins = sum(1 for a, b in zip(sorted(am), sorted(ap)) if b < a)
print(f"\n{'ALL PRs':<14}{len(am):>4}{mm//1000:>7}s{pm//1000:>7}s"
      f"   perf wins {wins}/{len(am)} (sorted-pair)")
