# cb-check: Incremental Persist (PR / old.bc → new.bc)

This document describes **`-enable-incremental-persist`**: hybrid reuse of
persisted SEGs when analyzing a *new* bitcode against a store produced from an
*older* bitcode (typical CI: baseline on `main`, re-analyze after a pull
request).

Related:

- [cb-check-modes.md](./cb-check-modes.md) — normal / store / pure load
- [producing-bitcode.md](./producing-bitcode.md) — gllvm + typed-pointer `.bc` recipes

## When to use which mode

| Goal | Flags | Bitcode |
|------|--------|---------|
| Full analysis, no disk | *(none)* | any |
| Save SEGs for later | `-persist-dir=DIR` | **same** as later load |
| Re-run checkers only | `-enable-load-project-from-persistence -persist-dir=DIR` | **identical** to store |
| **PR / changed code** | **`-enable-incremental-persist -persist-dir=DIR`** | **new** bc; store from **old** |

**Do not** pure-load `new.bc` from a store of `old.bc`. Pure load has no dirty
detection and will reattach stale SEGs to changed functions if hierarchical
keys still resolve.

## Prerequisites

1. **cb-check** built from a tree that includes incremental persist
   (branch `feature/incremental-persist-reuse` or later merge to main).
2. **LLVM 15 clang** with **typed pointers** when producing bitcode
   (`-Xclang -no-opaque-pointers`). Opaque-pointer BC is rejected.
3. **[gllvm](https://github.com/SRI-CSL/gllvm)** (`gclang` / `get-bc`) so a
   linked binary/shared library embeds bitcode that `get-bc` can extract.
4. Point `LLVM_COMPILER_PATH` at the LLVM 15 `bin` directory used by gclang.

Example environment used in recent runs:

```bash
export PATH="$HOME/go/bin:$HOME/tools/llvm15-official/bin:$PATH"
export LLVM_COMPILER_PATH=$HOME/tools/llvm15-official/bin
CBC=$HOME/github/FermatAnalyzer/build/tools/cb-check/cb-check
```

## Workflow

```text
old.bc  ── store (-persist-dir=./P) ──►  ./P/{seg,pts,callgraph}/
                                              │
         each PR: recompile → new.bc          │
                                              ▼
new.bc  ── -enable-incremental-persist -persist-dir=./P ──► checkers
              dirty rebuild + SPEG only on dirty; clean SEGs lazy-load
```

### 1. Produce baseline bitcode (`old.bc`)

Use the **same** compile flags for every later `new.bc`. Examples used in
local multi-project benches:

**curl (cmake + shared libcurl):**

```bash
cmake -S . -B build-gllvm -G Ninja \
  -DCMAKE_C_COMPILER=gclang \
  -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' \
  -DCMAKE_BUILD_TYPE=Debug \
  -DBUILD_SHARED_LIBS=ON \
  -DCURL_USE_OPENSSL=OFF -DCURL_DISABLE_LDAP=ON -DCURL_USE_LIBPSL=OFF
ninja -C build-gllvm
get-bc -o old.bc build-gllvm/lib/libcurl-d.so.4.8.0   # name may vary
```

**darknet (Makefile):**

```bash
make -j$(nproc) CC=gclang CPP=gclang++ DEBUG=1 GPU=0 \
  CFLAGS='-Wall -Wno-unused-result -Wno-unknown-pragmas -Wfatal-errors -fPIC -O0 -g -Xclang -no-opaque-pointers'
get-bc -o old.bc darknet
```

**libuv (cmake):**

```bash
cmake -S . -B build-gllvm -G Ninja \
  -DCMAKE_C_COMPILER=gclang \
  -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' \
  -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=OFF
ninja -C build-gllvm
get-bc -o old.bc build-gllvm/libuv.so.1.0.0
```

### 2. Store (once per baseline)

Flags used for **SEG-phase** timing and PR benches (no checkers):

```bash
$CBC \
  --hide-progress-bar \
  -nworkers=16 \
  -enable-build-seg-only \
  -persist-dir=./persist_bench \
  old.bc
```

With checkers (example NPD):

```bash
$CBC \
  --hide-progress-bar \
  -nworkers=16 \
  -segbuilder-aa=falconplus \
  --ps-npd --enable-heap-alloc-failure --psa-enable-arg-symbol \
  --psa-enable-side-effect-source \
  -persist-dir=./persist_bench \
  --report=store-report.json \
  old.bc
```

Expect `[Dumping SEG]` and files under `./persist_bench/seg/` (one SEG + one
`.fp` fingerprint per function).

**Tip:** Use a **dedicated** persist directory per project/baseline
(`persist_bench`, `persist_curl`, …). Do not mix stores from different
programs or different compile flags.

### 3. Build `new.bc` for a PR

Pattern used in benches: reset to the same commit as `old.bc`, copy changed
`.c`/`.h` files from the PR tip onto that tree, rebuild with **identical**
gllvm flags, then `get-bc -o new.bc …`.

```bash
# example: apply PR source files onto baseline, then rebuild (same flags as old.bc)
git fetch origin pull/NNNN/head:pr-NNNN
# copy listed .c/.h from pr-NNNN into the working tree, then rebuild + get-bc
```

If a PR does not apply cleanly (API drift), the tree may not compile; skip it
or use a synthetic IR-changing edit for a smoke test.

### 4. Incremental analysis on `new.bc`

SEG-only (matches recent wall-time benches):

```bash
$CBC \
  --hide-progress-bar \
  -nworkers=16 \
  -enable-build-seg-only \
  -enable-incremental-persist \
  -persist-dir=./persist_bench \
  new.bc
```

With checkers:

```bash
$CBC \
  --hide-progress-bar \
  -nworkers=16 \
  -enable-incremental-persist \
  -persist-dir=./persist_bench \
  --ps-npd --enable-heap-alloc-failure --psa-enable-arg-symbol \
  --psa-enable-side-effect-source \
  --report=pr-report.json \
  new.bc
```

Scratch baseline for comparison (same machine/flags, no persist):

```bash
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only new.bc
```

### 5. What a good incremental log looks like

```text
[Incremental persist] body-dirty: 1, +callers: 1, total dirty: 2
[Incremental persist] eagerly rebuilt 2 dirty SEGs (clean SEGs lazy-load on demand)
[SPEG] Start ... 1 functions to run (incremental; clean/loaded skipped)
[Dumping SEG] spends time ***…***
[Incremental persist] dumped 1 rebuilt SEGs (left … loaded untouched; clean-not-touched not loaded)
SEG-Building spends time ***…***
```

Compare to scratch: `[SPEG] Start ... N functions` with **N ≈ full module**.

`body-dirty: 0` is normal when the PR only changes code **not linked into**
this bitcode (e.g. curl tool sources when you only extract `libcurl`), or when
the IR is unchanged after compile. Incremental can still be faster because it
skips full SPEG.

## Bug-finding behavior (checker runs)

The benches above use `-enable-build-seg-only` (SEG phase only, no checkers).
When you run the **actual bug checkers** (`--ps-npd`, etc.) in incremental
mode, there is one crucial behavior to understand:

> **Incremental runs checkers only on the functions that changed** (the dirty
> set). It does **not** reproduce a full-module bug report.

Why: the clean SEGs are loaded from the store and **not re-checked**; SPEG /
checkers run only on the in-memory (dirty) SEGs. This is by design:

- It is the right behavior for **PR review**: "report what *this* change
  introduces", not "report every pre-existing bug".
- A finding in unchanged code will **not** appear in an incremental report,
  even though scratch (whole-module) would report it.
- To get the full whole-module report, run without `-enable-incremental-persist`.

### Exact commands to find a bug introduced by a PR

```bash
CBC=$HOME/github/FermatAnalyzer/build/tools/cb-check/cb-check
CHK="-segbuilder-aa=falconplus --ps-npd --enable-heap-alloc-failure --psa-enable-arg-symbol"

# 1) store clean baseline once
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only -persist-dir=./P old.bc

# 2) incremental check on the PR — checks ONLY the dirty functions
$CBC --hide-progress-bar -nworkers=16 -enable-incremental-persist -persist-dir=./P \
     $CHK --report=pr-report.json new.bc

# (for comparison) full-module check, no store
$CBC --hide-progress-bar -nworkers=16 $CHK --report=full-report.json new.bc
```

### Proven with an injected bug

A null-deref was injected into darknet (`int darknet_injected_npd_test(int x){
int *p=(int*)0; if(x>0)p=(int*)0; return *p; }`). After storing the clean
baseline, the incremental run:

- detected `body-dirty: 1` (precisely the injected function)
- ran SPEG on **1 function** (1020 clean SEGs loaded from store)
- **found 2 NPD findings, both in the injected function**

Scratch (whole-module) would report every pre-existing NPD in darknet too;
incremental correctly reports only the diff. See the `bug-finding-demo/`
folder in the repro repo for the committed `.bc` + full walkthrough.

## What “dirty” means

1. **Body-dirty** — function IR body fingerprint (structural mix of BB sizes /
   opcodes) does not match the `.fp` file next to the stored SEG, or no stored
   SEG exists.
2. **Caller-dirty (one hop)** — any function that **directly calls** a
   body-dirty function is also rebuilt so cross-SEG edges into the new callee
   are not left stale.

Clean functions are **not** eagerly deserialized. They are loaded on demand if
a later pass needs their SEG (lazy load). SPEG / Falcon AA runs only for
in-memory SEGs that were rebuilt this run (not for loaded clean SEGs).

## Storage layout

```text
persist_bench/
├── seg/
│   ├── fn_list_insert       # Cap'n Proto SEG (key = hierarchical func index)
│   ├── fn_list_insert.fp    # body fingerprint (decimal uint64 text)
│   └── ...
├── pts/                     # Falcon points-to (same hierarchical keys)
└── callgraph/
```

SEG filenames use **hierarchical LLVM value indices** (e.g. `fn_foo`,
`i_foo_0_3`), not module-wide counters. That is what allows the same function
in `old.bc` and `new.bc` to share a key when IR is unchanged.

## Implementation map

| Piece | Role |
|-------|------|
| `lib/Transform/LLVMValueIndexer.cpp` | Hierarchical value/type indices; cycle-safe types; no huge constant explode |
| `lib/Persistence/SEGSwap.cpp` | SEG I/O, `functionBodyFingerprint`, `*.fp` read/write |
| `lib/IR/SEG/SymbolicExprGraphBuilder.cpp` | Dirty set, eager rebuild, lazy load, dump only rebuilt SEGs |
| `lib/Analysis/Alias/PathSensitiveAADriver/AADriver.cpp` | SPEG only for non-loaded SEGs; pts load+store in incremental mode |
| `lib/Schema/SEGSerializer.cpp` | Null-safe cross-SEG resolve when callee SEG missing |
| `lib/Persistence/PersistOptions.cpp` | `-enable-incremental-persist` |

## Requirements and caveats

1. **Same analyzer build** for store and incremental (hierarchical indices +
   fingerprints must match the format that wrote the store).
2. **Typed-pointer bitcode** for this tree’s LLVM 15 / cb-check (e.g. clang
   `-Xclang -no-opaque-pointers` when producing `.bc`).
3. **Same compile flags** for `old.bc` and `new.bc` (optimization, defines,
   feature toggles). Different flags invalidate reuse.
4. **Re-store** after large baseline moves (rebase of main, mass renames, or
   flag changes that rewrite IR shape).
5. **Fingerprint is structural IR**, not source text: comment-only edits do not
   dirty; applying only non-linked files yields `body-dirty: 0`.
6. **One-hop callers only**: a change deep in a call graph may leave distant
   callers with loaded SEGs whose cross-edges into dirty callees are dropped
   (null-safe) rather than fully rebuilt.
7. **Scale**: medium programs often see large wall-time wins after one store.
   Very large modules may be neutral or slower—fixed IR prep + dirty expansion
   can dominate (those projects were dropped from this bench suite).
8. **Static `cb-check`**: stdout may be fully buffered when redirected; use
   `script -q -c '…' logfile` (or a TTY) if logs look empty while the process
   runs.
9. **Store vs load gating**: store mode (`-persist-dir` alone) must not hybrid
   load; pure load only with `-enable-load-project-from-persistence` (issue #10).

## Measured results (SEG build only; indicative)

Internal multi-PR runs on one machine (`-enable-build-seg-only`,
`-nworkers=16`). **Not** a CI guarantee—always re-measure on your hardware.

| Project | Store | SEGs (approx) | Inst (approx) | PR sample | Avg inc | Avg scratch | Wins / note |
|---------|------:|--------------:|--------------:|-----------|--------:|------------:|-------------|
| libuv | ~3s | ~0.8k | ~50k | 10–20 PRs | ~1s | ~2s | ~50% wall; SEG phase much cheaper |
| **curl** | **~13s** | **~2.3k** | **~218k** | **10 PRs** | **~4.6s** | **~10s** | **10/10**, med ~53% |
| darknet | ~140s | ~1.0k | ~122k | 10–20 | ~42s | ~78s | ~45% wall |

**Interpretation used in practice:**

- **curl / darknet / libuv** (and the other medium projects in `bc/`): good fit
  for CI incremental after one store.
- Prefer comparing **SEG-Building** time and SPEG function count in logs, not
  only wall clock, when debugging.

### End-to-end recipe used for curl (10 PRs)

```bash
export PATH="$HOME/go/bin:$HOME/tools/llvm15-official/bin:$PATH"
export LLVM_COMPILER_PATH=$HOME/tools/llvm15-official/bin
CBC=$HOME/github/FermatAnalyzer/build/tools/cb-check/cb-check

# store once
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
  -persist-dir=./persist_bench old.bc

# per PR: apply sources → rebuild new.bc → compare
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
  -enable-incremental-persist -persist-dir=./persist_bench new.bc
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only new.bc   # scratch
```

## Minimal check

```bash
# Store
cb-check -enable-build-seg-only -persist-dir=./P -hide-progress-bar -nworkers=16 old.bc

# Incremental (same or slightly changed new.bc)
cb-check -enable-build-seg-only -enable-incremental-persist -persist-dir=./P \
  -hide-progress-bar -nworkers=16 new.bc
```

Success signals:

- Incremental log contains `[Incremental persist] body-dirty: …`
- SPEG line reports far fewer functions than a full scratch run when few bodies
  changed
- Exit 0; no `Oops, runtime error` during load

## See also

- [producing-bitcode.md](./producing-bitcode.md) — how to compile projects to `.bc`
- [cb-check-modes.md](./cb-check-modes.md) — normal / store / pure load
- Issue #10 — store mode must not hybrid-load when only `-persist-dir` is set
- Branch `feature/incremental-persist-reuse` — feature implementation history
