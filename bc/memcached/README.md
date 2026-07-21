# `bc/memcached/` — memcached bitcode for cb-check incremental-persist
This folder holds typed-pointer LLVM 15 bitcode for **memcached**, used as the input for the `cb-check` incremental-persist benchmark (`scripts/run_bench.sh`).
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
```bash
# how each .bc was built (same for old.bc and every pr-*.bc)
autoreconf -fi ; automake --add-missing --copy ; ./configure CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' --with-libevent=<libevent prefix> ; make
get-bc -o <file>.bc <artifact>
```
See [`docs/producing-bitcode.md`](../../docs/producing-bitcode.md) for the full recipe.
## Reproduce the results
Three explicit `cb-check` invocations reproduce one data point: **store** the baseline once, then run a sample **incremental** (reuses stored SEGs) and **scratch** (no store) to compare.
```bash
CBC=$HOME/github/FermatAnalyzer/build/tools/cb-check/cb-check

# 1) store the baseline once (writes ./persist/memcached/seg/ ...)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -persist-dir=./persist/memcached bc/memcached/old.bc

# 2) incremental on a PR's bitcode (loads clean SEGs, rebuilds dirty)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -enable-incremental-persist -persist-dir=./persist/memcached bc/memcached/pr-NNNN.bc

# 3) scratch on the same bitcode (no store; full rebuild)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only bc/memcached/pr-NNNN.bc
```
Run steps 2–3 for each `pr-*.bc` in this folder. Compare the `SEG-Building spends time ***...***` line and the `[Incremental persist] body-dirty: N, +callers: M` line. Incremental wins when `inc` wall-time < `scratch` wall-time.
Result columns and log fields are explained in [`../../docs/cb-check-incremental-persist.md`](../../docs/cb-check-incremental-persist.md) and [`../../README.md`](../../README.md#result-columns).
## Files in this folder (6 total)
| File | PR / source | Title | Changed C/C++ files |
|------|-------------|-------|---------------------|
| `old.bc` (1.6M) | baseline `2d51e36` | — | — |
| `pr-1050.bc` (1.6M) | [#1050](https://github.com/memcached/memcached/pull/1050) | ? | ? |
| `pr-1074.bc` (1.6M) | [#1074](https://github.com/memcached/memcached/pull/1074) | ? | ? |
| `pr-1110.bc` (1.6M) | [#1110](https://github.com/memcached/memcached/pull/1110) | ? | ? |
| `pr-1215.bc` (1.6M) | [#1215](https://github.com/memcached/memcached/pull/1215) | ? | ? |
| `pr-1233.bc` (1.6M) | [#1233](https://github.com/memcached/memcached/pull/1233) | ? | ? |
