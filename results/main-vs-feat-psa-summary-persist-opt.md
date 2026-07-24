# A/B: main vs feat/psa-summary-persist-opt

**Date:** 2026-07-24
**Branches:** `main` @ `5d734a77` vs `feat/psa-summary-persist-opt` @ `f5b6ba6e`
**Binaries:** `/tmp/cb-check-main`, `/tmp/cb-check-feat` (both Release/NDEBUG, identical LLVM/z3)

## Bottom line

The feature (PSA summary persistence, folded into `-enable-incremental-persist`)
has **zero impact on the build-seg-only benchmark** and delivers an
**incremental full-analysis skip** for reuse.

## Key finding: build-seg-only = no impact

The bench harness runs `-enable-build-seg-only`, which skips the entire
checker pipeline (`cb-check.cpp:898`). PSAChecker / TraceSerializer are
**never called**. Verified: 0 psa/ files written in build-seg-only mode.

| project | store main/feat | inc main/feat |
|---------|----------------|---------------|
| c-ares (9 PR) | 3.9s / 3.9s | 1.1s / 1.1s |
| libuv (20 PR) | 5s / 5s | <1s / <1s |
| libjpeg-turbo (8 PR) | 72s / 61s | 19s / 20s |
| openssl (3 PR) | 122s / 114s | 40s / 39s |

All within noise (±7%). Raw data: `/tmp/ab_seg.tsv`.

## Full-analysis: the feature's actual domain

PSA summary persistence only activates with `-enable-incremental-persist` in
full analysis (no `-enable-build-seg-only`).

### Incremental skip (the win)

A function is skipable iff its SEG fingerprint matches (unchanged IR) AND no
transitive callee is dirty. Skipable functions load their stored summary and
skip rechecking.

| run | time |
|-----|------|
| main + `-enable-incremental-persist` (full) | **155s** |
| feat, no flag (normal GC) | **145s** |
| feat store run (old.bc) | slow (Z3-bound, see below) |
| feat reuse run (same bc, all skipable) | **22ms** (tiny case) |

The reuse run skips all checking — summaries loaded from disk.

### Store run: Z3-bound (known limitation)

Serializing a PSASummary calls `SMTExpr::getSymbol()` → `Z3_ast_to_string`,
which shares a Z3 context (not thread-safe). The call is serialized via
`SummaryBase::SMTContextLock`. This makes serialize ~1s/summary, dominated
by Z3 symbol formatting.

For large projects (c-ares: 502 summaries, nghttp2: 461+) the store run
exceeds a 600s budget. This is a one-time cost (paid on old.bc); subsequent
incremental runs only serialize dirty functions (few, fast).

**Not optimizable without per-thread Z3 contexts** (major SMT-layer rework,
out of scope for issue #20).

## Root-cause notes

1. **Original 4x regression**: end-of-run SERIAL serialize (450s) + disabled
   GC. Now: parallel serialize during GC + skip.
2. **Concurrency crash in parallel serialize**: `getSymbol()` touches the
   shared Z3 context. Fixed by `SMTContextLock` around just that call.
3. **Skip correctness**: transitive dirty propagation (reverse BFS up call
   graph). A caller of a dirty function is never skipped (its summary
   depends on the changed callee).
