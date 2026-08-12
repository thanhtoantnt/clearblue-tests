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

### 2. Store mode — `-persist-dir=<dir>`

Identical to normal mode, **plus** after building each SEG (and running alias
analysis on it), the SEG is serialized to disk. The checkers still run on the
in-memory SEGs as usual.

```bash
fermat-check -segbuilder-aa=falconplus -ps-npd -ps-uaf -psa-enable-side-effect-source \
  -persist-dir=/path/to/persist \
  --report=report-save.json app.bc
```

`-persist-dir` writes one file per function under `<dir>/seg/`.

### 3. Load mode — `-enable-load-project-from-persistence -persist-dir=<dir>`

`SymbolicExprGraphBuilder` **deserializes** the SEGs from `<dir>/seg/` instead
of rebuilding them, **skips alias-analysis recompute** (the persisted SEGs
already contain the alias-analysis-built state — interface/pseudo nodes,
points-to summaries), then the checkers run on the loaded SEGs.

```bash
fermat-check -segbuilder-aa=falconplus -ps-npd -ps-uaf -psa-enable-side-effect-source \
  -enable-load-project-from-persistence -persist-dir=/path/to/persist \
  --report=report-load.json app.bc
```

Use the **same bitcode** for the store run and the load run; the persisted SEG
files are keyed by the LLVM value index of each function, which is stable for a
given bitcode.

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

```
<persist-dir>/
└── seg/
    ├── <funcIndex>      # one file per function, named by the function's LLVM value index
    └── ...
```

- **Format**: Cap'n Proto binary schema (see `lib/Schema/`).
- **Per-file contents**: the function's SEG (nodes, intra-function edges) **and**
  its cross-SEG (call-site) edges that reference other functions' SEGs.
- Cross-SEG edges are loaded in a second pass (`deserializeCrossSEGEdgesFromStorage`)
  after every per-function SEG exists, so cross-function node references resolve.

## Flags

| flag | default | meaning |
|------|---------|---------|
| `-persist-dir=<dir>` | _(empty)_ | Persistence workspace. Aliases: `-persist-store-dir`, `-persist-load-dir`. |
| `-enable-load-project-from-persistence` | off | Load SEGs from `<dir>` instead of building. |
| `-segbuilder-aa=<aa>` | `falconplus` | Alias analysis: `falconplus`, `falcon`, `simple`, `tuna`. |
| `-nworkers=<n>` | min(cores, 10) | Worker threads for SEG building and checking. `1` = serial/deterministic. |
| `-enable-index` | off | Run `IndexBuilder` after the SEG producer. |
| `-seg-hash-dump-file=<file>` | _(empty)_ | Dump a JSON of SEG hashes (for change detection between builds). |
| `-enable-build-seg-only` | off | (Hidden) Build SEGs and stop; skip checkers. |

## Typical workflow

```bash
# 1. store — build + alias-analyze + persist SEGs (and still report bugs)
fermat-check -segbuilder-aa=falconplus -ps-npd -ps-uaf -psa-enable-side-effect-source \
  -persist-dir=./persist \
  --report=report-save.json --report-pass-line=0 -hide-progress-bar -omit-no-dbginfo \
  app.bc

# 2. load — reload SEGs, skip rebuild + AA, report bugs again
fermat-check -segbuilder-aa=falconplus -ps-npd -ps-uaf -psa-enable-side-effect-source \
  -enable-load-project-from-persistence -persist-dir=./persist \
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
fermat-check ... -nworkers=1 -persist-dir=./persist app.bc           # store
fermat-check ... -nworkers=1 -enable-load-project-from-persistence -persist-dir=./persist app.bc  # load
```

### The bitcode must match

The persisted SEG files are keyed by function LLVM value index. If the bitcode
changes (recompiled, different flags), the indices change and load mode will
fail to find the files or load stale SEGs. Re-run store mode after any bitcode
change. Use `-seg-hash-dump-file` to detect SEG drift between builds.

### Segfault on load (issue #6)

A previous load-path bug caused `-enable-load-project-from-persistence` to
segfault when deserializing value-less pseudo operand nodes. The fix makes
`SymbolicExprGraphBuilder` the SEG producer in all modes and reconstructs
placeholder values during deserialization. If load mode crashes, first confirm
you are running a build that includes the issue #6 fix.
