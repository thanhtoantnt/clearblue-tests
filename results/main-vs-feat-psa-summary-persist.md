# A/B: main vs feat/psa-summary-persist-opt

**Date:** 2026-07-24
**Branches:** `main` @ `5d734a77` vs `feat/psa-summary-persist-opt` @ `49c80f53`
**Binaries:** `/tmp/cb-check-main`, `/tmp/cb-check-feat` (both Release/NDEBUG, identical LLVM/z3)

## Key finding: two modes, two different answers

### 1. build-seg-only mode (what `run_bench.sh` uses) — NO IMPACT

The bench harness runs `-enable-build-seg-only`, which skips the entire
checker pipeline (`cb-check.cpp:898`). PSAChecker / TraceSerializer are
**never called**. Both binaries execute identical SEG-persist code.

Control-flow proof: all changed files (PSAChecker.cpp, TraceSerializer.cpp,
SchemaInterface.h, trace_schema_impl.cpp) are only reachable from
PSAChecker, which only runs when `!enable_build_seg_only`.

| project | store main/feat | inc main/feat (median) |
|---------|----------------|------------------------|
| c-ares (1.8M, 9 PR) | 3s / 3s (-3%) | 1s / 1s (-1%) |
| libuv (1.3M, 20 PR) | 5s / 5s (-1%) | <1s / <1s (-3%) |
| libjpeg-turbo (4.2M, 8 PR) | 72s / 61s (-14%) | 19s / 20s (+2%) |
| openssl (25M, 3 PR) | 122s / 114s (-7%) | 40s / 39s (-4%) |

All within noise (±7%). Raw data: `/tmp/ab_seg.tsv`.

### 2. full-analysis mode (the ONLY mode that runs PSA persist) — 4x REGRESSION

PSA summary persistence only activates with `-enable-incremental-persist`
in full analysis (no `-enable-build-seg-only`).

**nghttp2 (1M, 648 SEGs, 267 with summaries), single store run:**

| config | wall time | rc |
|--------|-----------|----|
| main + `-enable-incremental-persist` | **155s** | 0 (done) |
| feat, no flag (normal GC, no PSA persist) | **145s** | 0 (done) |
| feat + `-enable-incremental-persist` | **>600s** | 124 (TIMEOUT) |

Checking completes in all three (log: "PSA Checking: 100%" + "Record Num").
The cost is the **serialize phase** at `releaseAllMemory()`: 267 real
summaries × ~1.7s/each ≈ 450s+. Non-persist checking is unaffected
(feat-no-flag ≈ main).

### Why slow

`releaseAllMemory()` serializes all summaries single-threaded at end of
run. Each serialize walks the summary's trace trees + SEGNode refs via
Cap'n Proto. Real summaries (deep traces) are ~1.7s each vs sub-ms for
the tiny 3-function test case.

### Fix direction (not done)

Serialize is embarrassingly parallel (267 independent files). Parallelize
across the thread pool like the SEG dump loop does. Alternatively, serialize
per-function in `releaseMemory(F)` — but the original per-F approach crashed
(use-after-free, bug #19 territory) which is why store moved to end-of-run.
