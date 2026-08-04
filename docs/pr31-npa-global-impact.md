# PR #31 — NPA formal-arg change vs baseline `--ps-npd`

## Status

**NPA hunks dropped from PR #31** after Juliet CWE476 CI failure (empty/invalid
report JSON on normal `--ps-npd`). Ship ExtraCheck-only. Keep this note if the
NPA formal-arg idea is retried later.


Track later: does the **global** NPA tweak in
[FermatAnalyzer#31](https://github.com/fermat-hkrc/FermatAnalyzer/pull/31)
change full (non-incremental) `--ps-npd` results vs main **without** that
change?

Issue #30 fix has two parts. Only one is incremental-scoped.

| Piece | Where | Scope | Closed #30? |
|-------|--------|--------|-------------|
| **ExtraCheck** clean callee cone | `PSAChecker` | only `--enable-incremental-persist` + non-empty dirty | **Yes** (repro: inc `new` → TotalBugs=1) |
| **NPA** formal pointer args as unk / not must-not-null | `NullPtrAnalysis` | **all** NPD runs (default null analysis on) | **No** alone — did not cold-store `myDeref` under `-O0` |

## What NPA changed (#31)

In `lib/Analysis/GVFA/NullPtrAnalysis.cpp`:

1. Seed formal **pointer** args as unk (skip `nonnull` / dereferenceable).
2. Mark those arg seeds in `unk_ptrs` (BFS only inserted edge targets).
3. `varMustNotNull(Argument*)` → `false` unless nonnull/deref annotated.

Intent: pure-sink callees (e.g. `myDeref(int *p) { return *p; }`) emit **input**
summaries when analyzed, so dirty callers / future PSA **load** can glue
source→sink without rechecking the whole cone.

## Why it didn’t populate `myDeref` summary at `-O0`

Typical unoptimized IR:

```llvm
define void @myDeref(i32* %0) {
  %2 = alloca i32*
  store i32* %0, i32** %2
  %3 = load i32*, i32** %2
  %4 = load i32, i32* %3   ; check sees %3, not Argument %0
}
```

NPD null-filters the **deref pointer operand** (`%3`), not the raw formal.
Early `varMustNotNull` only special-cases `Argument`. Unless VFG unk-prop
marks the load/alloca path, NPA still drops the sink → empty InSmry → no
`persist/.../psa/fn_*myDeref*` on cold store.

Observed on issue #30 bitcode:

- NPA-on + #31 NPA hunks: cold PSA dir **missing** `myDeref`
- `--ps-npd-enable-null-analysis=false`: `myDeref` summary **present**
- ExtraCheck on incremental dirty pass: **TotalBugs=1** (real #30 fix)

## What to measure later (baseline `--ps-npd`)

Compare **same bitcode**, **no** `--enable-incremental-persist`:

| Build A | Build B |
|---------|---------|
| `main` (or #31 with NPA hunks reverted) | #31 as merged (ExtraCheck + NPA) |

Same flags, e.g.:

```bash
$CBC <module.bc> --ps-npd --omit-no-dbginfo --report=out.json
# optional: wall time / SMT Check Times from stderr
```

Record per target (use this repo’s `bc/` sets + any larger corpus):

- `TotalBugs` / per-bug-type counts (JSON report)
- wall time, `SMT Check Times` if printed
- optional: size/count of PSA summaries if you also run a **store** pass
  (`--enable-incremental-persist` cold) — InSmry volume may grow even when
  bug count is flat

**Pass criteria (suggested):**

- No unexpected bug-count delta on known-clean / known-bug baselines
- If bugs match: note any systematic time or summary-volume regression
- If bugs differ: file follow-up (NPA formal-arg policy vs alloca/load paths)

## Optional controls

```bash
# isolate NPA off (both builds should agree more if NPA is the wedge)
$CBC <bc> --ps-npd --ps-npd-enable-null-analysis=false --omit-no-dbginfo --report=...
```

If A vs B match with NPA disabled but diverge with NPA on → attribute to formal-arg seeds / `varMustNotNull`, not ExtraCheck.

## Related

- Issue: FermatAnalyzer #30 (incremental NPD FN through clean callee)
- PR: FermatAnalyzer #31
- ExtraCheck cost while load stays off: see PR body; separate from this NPA note
- Re-enable PSA summary load only after constraint cache is real (`KEnablePsaSummaryLoad`)
