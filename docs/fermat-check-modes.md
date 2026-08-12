# fermat-check: Normal Mode and Store/Load Mode

This document describes the three operating modes of `fermat-check`, the
FermatAnalyzer static analyzer, with a focus on the SEG (Symbolic Expr Graph)
persistence feature in `lib/Persistence/`.

For **PR / old.bc → new.bc** reuse (hybrid load + rebuild), see
[fermat-check-incremental-persist.md](./fermat-check-incremental-persist.md)
(`-enable-incremental-persist`).

For compiling projects into typed-pointer bitcode (`gclang` / `get-bc`), see
[producing-bitcode.md](./producing-bitcode.md).

## Background

`fermat-check` analyzes LLVM bitcode in three phases:

1. **IR preparation** — canonicalization passes (`mem2reg`, loop breaking,
   lowering irreducible CFG, etc.).
2. **SEG + alias analysis** — `SymbolicExprGraphBuilder` builds a per-function
   SEG and runs the chosen alias analysis (`falconplus` by default). This is
   the most expensive phase.
3. **Checking** — path-sensitive checkers (`-ps-npd`, `-ps-uaf`, BOF, …) run
   over the SEGs via `ParallelScheduler` / `CBChecker` and emit bug reports.

The SEG persistence feature lets phase 2 be **serialized to disk** in one run
and **reloaded** in later runs, so the expensive build + alias analysis is done
once and reused.

## The three modes

### 1. Normal mode (default)

Build SEGs from bitcode, run alias analysis, run checkers. No persistence.

```bash
fermat-check -segbuilder-aa=falconplus -ps-npd -ps-uaf -psa-enable-side-effect-source \
  --report=report.json app.bc
```

### 2. Store mode — `-serialize-seg`

Identical to normal mode, **plus** after building every SEG (and running alias
analysis on it), each SEG is written as JSON under `-store-models-dir`. The
checkers still run on the in-memory SEGs as usual.

```bash
fermat-check -segbuilder-aa=falconplus -ps-npd -ps-uaf -psa-enable-side-effect-source \
  -serialize-seg -store-models-dir=/path/to/persist \
  --report=report-save.json app.bc
```

### 3. Load mode — `-load-seg`

`SymbolicExprGraphBuilder` **reads every SEG from JSON** under
`-store-models-dir` instead of building them, **skips alias-analysis
recompute** (the persisted SEGs already contain the alias-analysis-built
state — interface/pseudo nodes, points-to summaries), then the checkers run
on the loaded SEGs.

```bash
fermat-check -segbuilder-aa=falconplus -ps-npd -ps-uaf -psa-enable-side-effect-source \
  -load-seg -store-models-dir=/path/to/persist \
  --report=report-load.json app.bc
```

Use the **same bitcode** for the store run and the load run (or override the
path module component with `-store-module-name` so both runs share one
directory). Pure load has no dirty detection — do not pure-load a changed
`new.bc` from a store of `old.bc`; use `-enable-incremental-persist` for that.

## Pass pipeline

Relevant passes, in order (see `tools/fermat-check/fermat-check.cpp`):

```
IR canonicalization (mem2reg, LowerSwitch, IrredCFGElim, LoopBreak, ...)
  -> IndexLLVMValueLocationPass      # index every Value/Type to a stable int id
  -> SymbolicExprGraphBuilder        # SEG producer: build (normal/store) or load (load)
  -> [IndexBuilder]                  # only if -enable-index
  -> ParallelScheduler / CBChecker   # run checkers, emit bug report
```

`IndexLLVMValueLocationPass` **must** run before the SEG producer in both store
and load mode: persisted SEGs reference LLVM values/types by their integer
index (not by pointer), so the index must exist before serialization and before
deserialization. `fermat-check` always schedules it before the builder.

## Storage layout

Path root is `-store-models-dir` (default `fa-out`). Under it, files are
grouped by module name (`-store-module-name`, else the input bitcode file
name):

```
<store-models-dir>/
└── <module-name>/
    ├── func_value_type_index.json   # module LLVM value/type index
    └── SEG/
        ├── <funcName>.json          # one SEG JSON per function
        ├── <funcName>.json.fp       # body fingerprint beside each SEG
        └── ...
```

- **Format**: JSON (see `lib/Persistence/JSON/`).
- **Per-SEG file**: the function's SEG (nodes, intra-function edges) **and**
  its cross-SEG (call-site) edges that reference other functions' SEGs.
- **Fingerprint (`.fp`)**: written next to each SEG on store; pure `-load-seg`
  refuses a SEG when the `.fp` is missing or the IR body no longer matches
  (re-run with `-serialize-seg` to refresh).
- Cross-SEG edges are loaded in a second pass after every per-function SEG
  exists, so cross-function node references resolve.

## SEG persistence flags

SEGs are expensive to build; you can store them once and replay them.
`-serialize-seg` and `-load-seg` are `cl::Hidden` (not shown in plain `-help`;
use `-help-hidden`).

| Option | Meaning | Default |
|--------|---------|---------|
| `-serialize-seg` | Full store: build every SEG and write it as JSON | off |
| `-load-seg` | Full load: read every SEG from JSON instead of building | off |
| `-store-models-dir <dir>` | Root directory for the persistence files | `fa-out` |
| `-store-module-name <name>` | Module name used in the store path | derived from input file name |

Related (hybrid PR workflow — see
[fermat-check-incremental-persist.md](./fermat-check-incremental-persist.md)):

| Option | Meaning | Default |
|--------|---------|---------|
| `-enable-incremental-persist` | Hybrid: reuse SEGs whose body fingerprint still matches; rebuild dirty cone | off |

Other useful flags:

| flag | default | meaning |
|------|---------|---------|
| `-segbuilder-aa=<aa>` | `falconplus` | Alias analysis: `falconplus`, `falcon`, `simple`. |
| `-nworkers=<n>` | min(cores, 10) | Worker threads for SEG building and checking. `1` = serial/deterministic. |
| `-enable-build-seg-only` | off | (Hidden) Build SEGs and stop; skip checkers. |

## Typical workflow

```bash
# 1. store — build + alias-analyze + persist SEGs (and still report bugs)
fermat-check -segbuilder-aa=falconplus -ps-npd -ps-uaf -psa-enable-side-effect-source \
  -serialize-seg -store-models-dir=./persist \
  --report=report-save.json --report-pass-line=0 -hide-progress-bar -omit-no-dbginfo \
  app.bc

# 2. load — reload SEGs, skip rebuild + AA, report bugs again
fermat-check -segbuilder-aa=falconplus -ps-npd -ps-uaf -psa-enable-side-effect-source \
  -load-seg -store-models-dir=./persist \
  --report=report-load.json --report-pass-line=0 -hide-progress-bar -omit-no-dbginfo \
  app.bc
```

Both runs should report the same `TotalBugs` when run deterministically (see
caveats below).

## Caveats

### Load mode skips alias-analysis recompute

In load mode, `SymbolicExprGraphBuilder` does **not** call
`AADriver::compute` / `FalconAA::compute` again, because the persisted SEGs
already contain the alias-analysis-built SPEG interface and pseudo-argument /
pseudo-return nodes. Recomputing would try to re-build that interface on top of
the already-built SEG and trip internal consistency asserts. The checkers
consume the SEG state directly, so skipping the recompute is correct as long as
the SEG was persisted **after** alias analysis ran (which store mode does).

### Parallelism is non-deterministic

The analyzer is parallel-nondeterministic: two independent runs of the **same**
bitcode can report slightly different `TotalBugs` (a few percent) purely due to
scheduling, with no persistence bug. For an exact store==load equality check,
run both serially:

```bash
fermat-check ... -nworkers=1 -serialize-seg -store-models-dir=./persist app.bc           # store
fermat-check ... -nworkers=1 -load-seg -store-models-dir=./persist app.bc  # load
```

### The bitcode must match

SEG files live under `<store-models-dir>/<module-name>/SEG/` and are named by
sanitized function name (plus a short hash suffix on collisions). Each SEG has
a sibling `.fp` body fingerprint. Pure `-load-seg` requires matching IR bodies;
if the bitcode changes, either re-store with `-serialize-seg` or use
`-enable-incremental-persist` for dirty/rebuild. Keep `-store-models-dir` (and
`-store-module-name` if set) identical between store and load.

### Segfault on load (issue #6)

A previous load-path bug caused `-load-seg` to
segfault when deserializing value-less pseudo operand nodes. The fix makes
`SymbolicExprGraphBuilder` the SEG producer in all modes and reconstructs
placeholder values during deserialization. If load mode crashes, first confirm
you are running a build that includes the issue #6 fix.
