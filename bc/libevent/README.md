# `bc/libevent/` — libevent bitcode for fermat-check incremental-persist
This folder holds typed-pointer LLVM 15 bitcode for **libevent**, used as the input for the `fermat-check` incremental-persist benchmark (`scripts/run_bench.sh`).
## Layout
- **`old.bc`** — the stored baseline. Produced from the upstream source at commit [`e1f0335d`](https://github.com/libevent/libevent/commit/e1f0335d). `run_bench.sh` stores SEGs from this once; everything else is benchmarked against it.
- **`pr-<NNNN>.bc`** — one bitcode per pull request. Each was produced by applying that PR's source onto the baseline commit and recompiling with the **identical** flags used for `old.bc`. (Names with `pr-syn<N>.bc` are synthetic no-op edits, not real PRs.)
## Build configuration
| | |
|---|---|
| Upstream | `libevent/libevent` (<https://github.com/libevent/libevent>)
| Baseline commit | `e1f0335d`
| Artifact extracted | `libevent_core-2.2.so.1.0.1 (shared lib)`
| Toolchain | gllvm `gclang` + `get-bc`, LLVM 15, `-Xclang -no-opaque-pointers`
| Result size | `libevent_core (~30k inst)`
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
git clone https://github.com/libevent/libevent.git libevent
cd libevent
git checkout e1f0335d

# build + extract bitcode (artifact: libevent_core-2.2.so.1.0.1 (shared lib))
cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DEVENT__LIBRARY_TYPE=SHARED -DEVENT__DISABLE_OPENSSL=ON -DEVENT__DISABLE_MBEDTLS=ON -DEVENT__DISABLE_TESTS=ON -DEVENT__DISABLE_SAMPLES=ON
get-bc -o old.bc
```
### 2. Build `pr-NNNN.bc` (one per pull request)
Reset to the baseline, apply the PR's source, rebuild with the **same** command, and save under a new name:
```bash
git reset --hard e1f0335d
# fetch the PR ref and copy its changed .c/.h onto the tree
git fetch origin pull/NNNN/head:pr-NNNN
mb=$(git merge-base HEAD pr-NNNN)
git diff --name-only $mb pr-NNNN | grep -E '\.(c|h)$' | \
  while read f; do git show pr-NNNN:$f > $f; done
git branch -D pr-NNNN

# rebuild with the SAME command as step 1
cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DEVENT__LIBRARY_TYPE=SHARED -DEVENT__DISABLE_OPENSSL=ON -DEVENT__DISABLE_MBEDTLS=ON -DEVENT__DISABLE_TESTS=ON -DEVENT__DISABLE_SAMPLES=ON
get-bc -o pr-NNNN.bc
```
> `scripts/build_pr_bc.sh` automates steps 1-2 for every PR recorded in `results/<proj>/summary.tsv`; run it from the repo root: `./scripts/build_pr_bc.sh libevent`.
See [`docs/producing-bitcode.md`](../../docs/producing-bitcode.md) for the full recipe.
## Reproduce the results (fermat-check analysis)
Three explicit `fermat-check` invocations reproduce one data point: **store** the baseline once, then run a sample **incremental** (reuses stored SEGs) and **scratch** (no store) to compare.
```bash
CBC=$HOME/github/FermatAnalyzer/build/tools/fermat-check/fermat-check

# 1) store the baseline once (-serialize-seg → ./persist/libevent/<module>/SEG/*.json)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -serialize-seg -store-models-dir=./persist/libevent bc/libevent/old.bc

# 2) incremental on a PR's bitcode (loads clean SEGs, rebuilds dirty)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -enable-incremental-persist -store-models-dir=./persist/libevent bc/libevent/pr-NNNN.bc

# 3) scratch on the same bitcode (no store; full rebuild)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only bc/libevent/pr-NNNN.bc
```
Run steps 2–3 for each `pr-*.bc` in this folder. Compare the `SEG-Building spends time ***...***` line and the `[Incremental persist] body-dirty: N, +callers: M` line. Incremental wins when `inc` wall-time < `scratch` wall-time.
Result columns and log fields are explained in [`../../docs/fermat-check-incremental-persist.md`](../../docs/fermat-check-incremental-persist.md) and [`../../README.md`](../../README.md#result-columns).
## Files in this folder (13 total)
| File | PR / source | Title | Changed C/C++ files |
|------|-------------|-------|---------------------|
| `old.bc` (1.2M) | baseline `e1f0335d` | — | — |
| `pr-1867.bc` (1.2M) | [#1867](https://github.com/libevent/libevent/pull/1867) | cmake,autotools: add EVENT__DISABLE_RPC, EVENT__DISABLE_EVENT_TAGGING, | http.c, test/regress.c, test/regress_http.c, test/regress_ma |
| `pr-1868.bc` (1.2M) | [#1868](https://github.com/libevent/libevent/pull/1868) | event: skip update_time_cache() on non-blocking empty-heap loop iterat | event.c, test/bench_loop.c, test/regress.c |
| `pr-1869.bc` (1.2M) | [#1869](https://github.com/libevent/libevent/pull/1869) | test: add bench_bufferevent throughput benchmark (plaintext + OpenSSL) | test/bench_bufferevent.c |
| `pr-1871.bc` (1.2M) | [#1871](https://github.com/libevent/libevent/pull/1871) | Report SERVFAIL correctly to callbacks | evdns.c |
| `pr-1872.bc` (1.2M) | [#1872](https://github.com/libevent/libevent/pull/1872) | ws: free the connection on BEV_EVENT_ERROR, not only BEV_EVENT_EOF | ws.c |
| `pr-1873.bc` (1.2M) | [#1873](https://github.com/libevent/libevent/pull/1873) | Fix EVENT_BASE_FLAG_IGNORE_ENV bypass for EVENT_SHOW_METHOD | event.c, test/regress.c |
| `pr-1874.bc` (1.2M) | [#1874](https://github.com/libevent/libevent/pull/1874) | Support customizing TCP_KEEPINTVL and TCP_KEEPCNT for evutil | evutil.c, include/event2/util.h |
| `pr-1877.bc` (1.2M) | [#1877](https://github.com/libevent/libevent/pull/1877) | Fix GCC and clang warnings for 2.2 | http.c, sample/le-proxy.c, test/regress_buffer.c, test/regre |
| `pr-1879.bc` (1.2M) | [#1879](https://github.com/libevent/libevent/pull/1879) | fix a trivial comment typo | wepoll.c |
| `pr-1884.bc` (1.2M) | [#1884](https://github.com/libevent/libevent/pull/1884) | Fix a couple of mingw64 compilation errors. | include/event2/util.h, sample/https-client.c |
| `pr-1886.bc` (1.2M) | [#1886](https://github.com/libevent/libevent/pull/1886) | sample: Replace strcpy in http-server.c | sample/http-server.c |
| `pr-1892.bc` (1.2M) | [#1892](https://github.com/libevent/libevent/pull/1892) | bufferevent_ssl: opt-in per-call TLS latency timing (rdtsc/CLOCK_MONOT | bufferevent_ssl.c, evutil_time.c, include/event2/bufferevent |
