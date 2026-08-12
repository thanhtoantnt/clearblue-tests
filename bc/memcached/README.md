# `bc/memcached/` — memcached bitcode for fermat-check incremental-persist
This folder holds typed-pointer LLVM 15 bitcode for **memcached**, used as the input for the `fermat-check` incremental-persist benchmark (`scripts/run_bench.sh`).
## Layout
- **`old.bc`** — the stored baseline. Produced from the upstream source at commit [`2d51e36`](https://github.com/memcached/memcached/commit/2d51e36). `run_bench.sh` stores SEGs from this once; everything else is benchmarked against it.
- **`pr-<NNNN>.bc`** — one bitcode per pull request. Each was produced by applying that PR's source onto the baseline commit and recompiling with the **identical** flags used for `old.bc`. (Names with `pr-syn<N>.bc` are synthetic no-op edits, not real PRs.)
## Build configuration
| | |
|---|---|
| Upstream | `memcached/memcached` (<https://github.com/memcached/memcached>)
| Baseline commit | `2d51e36`
| Artifact extracted | `memcached (server binary)`
| Toolchain | gllvm `gclang` + `get-bc`, LLVM 15, `-Xclang -no-opaque-pointers`
| Result size | `memcached (~15k inst)`
## Reproduce the .bc files from source
The committed `.bc` files are self-contained, but you can rebuild any of them from the upstream source. The key rule: **`old.bc` and every `pr-*.bc` must use the identical toolchain and flags** so `fermat-check` fingerprints match.
### Prerequisites (once)
```bash
# gllvm wraps clang to embed bitcode -- https://github.com/SRI-CSL/gllvm
go install github.com/SRI-CSL/gllvm/cmd/gclang@latest
go install github.com/SRI-CSL/gllvm/cmd/get-bc@latest
# point gllvm at LLVM 15 (typed pointers), then put it on PATH
export LLVM_COMPILER_PATH=$HOME/tools/llvm15-official/bin
export PATH=$HOME/go/bin:$LLVM_COMPILER_PATH:$PATH
which gclang get-bc   # sanity check
```
### 1. Build `old.bc` (the baseline)
```bash
git clone https://github.com/memcached/memcached.git memcached
cd memcached
git checkout 2d51e36

# project-specific setup
# needs libevent: build it (see bc/libevent) then cmake --install <dir> --prefix /tmp/lev
./autogen.sh && autoreconf -fi && automake --add-missing --copy

# build + extract bitcode (artifact: memcached (server binary))
./configure CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' --with-libevent=/tmp/lev LDFLAGS='-L/tmp/lev/lib -Wl,-rpath,/tmp/lev/lib' CPPFLAGS='-I/tmp/lev/include' ; make
get-bc -o old.bc
```
### 2. Build `pr-NNNN.bc` (one per pull request)
Reset to the baseline, apply the PR's source, rebuild with the **same** command, and save under a new name:
```bash
git reset --hard 2d51e36
# fetch the PR ref and copy its changed .c/.h onto the tree
git fetch origin pull/NNNN/head:pr-NNNN
mb=$(git merge-base HEAD pr-NNNN)
git diff --name-only $mb pr-NNNN | grep -E '\.(c|h)$' | \
  while read f; do git show pr-NNNN:$f > $f; done
git branch -D pr-NNNN

# rebuild with the SAME command as step 1
./configure CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' --with-libevent=/tmp/lev LDFLAGS='-L/tmp/lev/lib -Wl,-rpath,/tmp/lev/lib' CPPFLAGS='-I/tmp/lev/include' ; make
get-bc -o pr-NNNN.bc
```
> `scripts/build_pr_bc.sh` automates steps 1-2 for every PR recorded in `results/<proj>/summary.tsv`; run it from the repo root: `./scripts/build_pr_bc.sh memcached`.
See [`docs/producing-bitcode.md`](../../docs/producing-bitcode.md) for the full recipe.
## Reproduce the results (fermat-check analysis)
Three explicit `fermat-check` invocations reproduce one data point: **store** the baseline once, then run a sample **incremental** (reuses stored SEGs) and **scratch** (no store) to compare.
```bash
CBC=$HOME/github/FermatAnalyzer/build/tools/fermat-check/fermat-check

# 1) store the baseline once (writes ./persist/memcached/seg/ ...)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -serialize-seg -store-models-dir=./persist/memcached bc/memcached/old.bc

# 2) incremental on a PR's bitcode (loads clean SEGs, rebuilds dirty)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -enable-incremental-persist -store-models-dir=./persist/memcached bc/memcached/pr-NNNN.bc

# 3) scratch on the same bitcode (no store; full rebuild)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only bc/memcached/pr-NNNN.bc
```
Run steps 2–3 for each `pr-*.bc` in this folder. Compare the `SEG-Building spends time ***...***` line and the `[Incremental persist] body-dirty: N, +callers: M` line. Incremental wins when `inc` wall-time < `scratch` wall-time.
Result columns and log fields are explained in [`../../docs/fermat-check-incremental-persist.md`](../../docs/fermat-check-incremental-persist.md) and [`../../README.md`](../../README.md#result-columns).
## Files in this folder (6 total)
| File | PR / source | Title | Changed C/C++ files |
|------|-------------|-------|---------------------|
| `old.bc` (1.6M) | baseline `2d51e36` | — | — |
| `pr-1050.bc` (1.6M) | [#1050](https://github.com/memcached/memcached/pull/1050) | ? | ? |
| `pr-1074.bc` (1.6M) | [#1074](https://github.com/memcached/memcached/pull/1074) | ? | ? |
| `pr-1110.bc` (1.6M) | [#1110](https://github.com/memcached/memcached/pull/1110) | ? | ? |
| `pr-1215.bc` (1.6M) | [#1215](https://github.com/memcached/memcached/pull/1215) | ? | ? |
| `pr-1233.bc` (1.6M) | [#1233](https://github.com/memcached/memcached/pull/1233) | ? | ? |
