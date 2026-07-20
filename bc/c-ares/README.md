# `bc/c-ares/` — c-ares bitcode for cb-check incremental-persist
This folder holds typed-pointer LLVM 15 bitcode for **c-ares**, used as the input for the `cb-check` incremental-persist benchmark (`scripts/run_bench.sh`).
## Layout
- **`old.bc`** — the stored baseline. Produced from the upstream source at commit [`589b5887`](https://github.com/c-ares/c-ares/commit/589b5887). `run_bench.sh` stores SEGs from this once; everything else is benchmarked against it.
- **`pr-<NNNN>.bc`** — one bitcode per pull request. Each was produced by applying that PR's source onto the baseline commit and recompiling with the **identical** flags used for `old.bc`. (Names with `pr-syn<N>.bc` are synthetic no-op edits, not real PRs.)
## Build configuration
| | |
|---|---|
| Upstream | `c-ares/c-ares` (<https://github.com/c-ares/c-ares>)
| Baseline commit | `589b5887`
| Artifact extracted | `libcares.so.2.19.4 (shared lib)`
| Toolchain | gllvm `gclang` + `get-bc`, LLVM 15, `-Xclang -no-opaque-pointers`
| Result size | `libcares (~40k inst)`
```bash
# how each .bc was built (same for old.bc and every pr-*.bc)
cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DCARES_SHARED=ON -DCARES_STATIC=OFF
get-bc -o <file>.bc <artifact>
```
See [`docs/producing-bitcode.md`](../../docs/producing-bitcode.md) for the full recipe.
## Reproduce the results
Three explicit `cb-check` invocations reproduce one data point: **store** the baseline once, then run a sample **incremental** (reuses stored SEGs) and **scratch** (no store) to compare.
```bash
CBC=$HOME/github/FermatAnalyzer/build/tools/cb-check/cb-check

# 1) store the baseline once (writes ./persist/c-ares/seg/ ...)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -persist-dir=./persist/c-ares bc/c-ares/old.bc

# 2) incremental on a PR's bitcode (loads clean SEGs, rebuilds dirty)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -enable-incremental-persist -persist-dir=./persist/c-ares bc/c-ares/pr-NNNN.bc

# 3) scratch on the same bitcode (no store; full rebuild)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only bc/c-ares/pr-NNNN.bc
```
Run steps 2–3 for each `pr-*.bc` in this folder. Compare the `SEG-Building spends time ***...***` line and the `[Incremental persist] body-dirty: N, +callers: M` line. Incremental wins when `inc` wall-time < `scratch` wall-time.
Result columns and log fields are explained in [`../../docs/cb-check-incremental-persist.md`](../../docs/cb-check-incremental-persist.md) and [`../../README.md`](../../README.md#result-columns).
## Files in this folder (10 total)
| File | PR / source | Title | Changed C/C++ files |
|------|-------------|-------|---------------------|
| `old.bc` (1.8M) | baseline `589b5887` | — | — |
| `pr-1244.bc` (1.8M) | [#1244](https://github.com/c-ares/c-ares/pull/1244) | Revert "Mark parameters in callbacks as const" (#1060); document non-m | include/ares.h, src/lib/ares_getnameinfo.c, src/tools/ahost. |
| `pr-1247.bc` (1.8M) | [#1247](https://github.com/c-ares/c-ares/pull/1247) | event: deliver failed-I/O completions in Win32 IOCP fallback (x86 even | src/lib/event/ares_event_win32.c |
| `pr-1251.bc` (1.8M) | [#1251](https://github.com/c-ares/c-ares/pull/1251) | getaddrinfo: ignore non-loopback localhost hosts entries | src/lib/ares_getaddrinfo.c |
| `pr-1254.bc` (1.8M) | [#1254](https://github.com/c-ares/c-ares/pull/1254) | Fix double-free in ares_requeue_queries() on connection close | src/lib/ares_close_sockets.c, src/lib/ares_conn.h, src/lib/a |
| `pr-1256.bc` (1.8M) | [#1256](https://github.com/c-ares/c-ares/pull/1256) | Regression: Query removal after random qid reuse | src/lib/ares_process.c |
| `pr-1257.bc` (1.8M) | [#1257](https://github.com/c-ares/c-ares/pull/1257) | reject rdata larger than the 16-bit rdlength field on write | src/lib/record/ares_dns_write.c |
| `pr-1258.bc` (1.8M) | [#1258](https://github.com/c-ares/c-ares/pull/1258) | size name buffers for the escaped presentation form | src/lib/ares_send.c, src/lib/record/ares_dns_name.c |
| `pr-1259.bc` (1.8M) | [#1259](https://github.com/c-ares/c-ares/pull/1259) | ares_destroy: support being called from within a query callback | src/lib/ares_cancel.c, src/lib/ares_destroy.c, src/lib/ares_ |
| `pr-1260.bc` (1.8M) | [#1260](https://github.com/c-ares/c-ares/pull/1260) | detach query before synchronous callback in end_query | src/lib/ares_process.c |
