# `bc/curl/` — curl bitcode for fermat-check incremental-persist
This folder holds typed-pointer LLVM 15 bitcode for **curl**, used as the input for the `fermat-check` incremental-persist benchmark (`scripts/run_bench.sh`).
## Layout
- **`old.bc`** — the stored baseline. Produced from the upstream source at commit [`bc440a89d4`](https://github.com/curl/curl/commit/bc440a89d4). `run_bench.sh` stores SEGs from this once; everything else is benchmarked against it.
- **`pr-<NNNN>.bc`** — one bitcode per pull request. Each was produced by applying that PR's source onto the baseline commit and recompiling with the **identical** flags used for `old.bc`. (Names with `pr-syn<N>.bc` are synthetic no-op edits, not real PRs.)
## Build configuration
| | |
|---|---|
| Upstream | `curl/curl` (<https://github.com/curl/curl>)
| Baseline commit | `bc440a89d4`
| Artifact extracted | `libcurl-d.so.4.8.0 (libcurl, shared, no OpenSSL/LDAP/libpsl)`
| Toolchain | gllvm `gclang` + `get-bc`, LLVM 15, `-Xclang -no-opaque-pointers`
| Result size | `libcurl (debug shared lib)`
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
git clone https://github.com/curl/curl.git curl
cd curl
git checkout bc440a89d4

# build + extract bitcode (artifact: libcurl-d.so.4.8.0 (libcurl, shared, no OpenSSL/LDAP/libpsl))
cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DBUILD_SHARED_LIBS=ON -DCURL_USE_OPENSSL=OFF -DCURL_DISABLE_LDAP=ON -DCURL_USE_LIBPSL=OFF
get-bc -o old.bc
```
### 2. Build `pr-NNNN.bc` (one per pull request)
Reset to the baseline, apply the PR's source, rebuild with the **same** command, and save under a new name:
```bash
git reset --hard bc440a89d4
# fetch the PR ref and copy its changed .c/.h onto the tree
git fetch origin pull/NNNN/head:pr-NNNN
mb=$(git merge-base HEAD pr-NNNN)
git diff --name-only $mb pr-NNNN | grep -E '\.(c|h)$' | \
  while read f; do git show pr-NNNN:$f > $f; done
git branch -D pr-NNNN

# rebuild with the SAME command as step 1
cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DBUILD_SHARED_LIBS=ON -DCURL_USE_OPENSSL=OFF -DCURL_DISABLE_LDAP=ON -DCURL_USE_LIBPSL=OFF
get-bc -o pr-NNNN.bc
```
> `scripts/build_pr_bc.sh` automates steps 1-2 for every PR recorded in `results/<proj>/summary.tsv`; run it from the repo root: `./scripts/build_pr_bc.sh curl`.
See [`docs/producing-bitcode.md`](../../docs/producing-bitcode.md) for the full recipe.
## Reproduce the results (fermat-check analysis)
Three explicit `fermat-check` invocations reproduce one data point: **store** the baseline once, then run a sample **incremental** (reuses stored SEGs) and **scratch** (no store) to compare.
```bash
CBC=$HOME/github/FermatAnalyzer/build/tools/fermat-check/fermat-check

# 1) store the baseline once (-serialize-seg → ./persist/curl/<module>/SEG/*.json)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -serialize-seg -store-models-dir=./persist/curl bc/curl/old.bc

# 2) incremental on a PR's bitcode (loads clean SEGs, rebuilds dirty)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -enable-incremental-persist -store-models-dir=./persist/curl bc/curl/pr-NNNN.bc

# 3) scratch on the same bitcode (no store; full rebuild)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only bc/curl/pr-NNNN.bc
```
Run steps 2–3 for each `pr-*.bc` in this folder. Compare the `SEG-Building spends time ***...***` line and the `[Incremental persist] body-dirty: N, +callers: M` line. Incremental wins when `inc` wall-time < `scratch` wall-time.
Result columns and log fields are explained in [`../../docs/fermat-check-incremental-persist.md`](../../docs/fermat-check-incremental-persist.md) and [`../../README.md`](../../README.md#result-columns).
## Files in this folder (11 total)
| File | PR / source | Title | Changed C/C++ files |
|------|-------------|-------|---------------------|
| `old.bc` (6.6M) | baseline `bc440a89d4` | — | — |
| `pr-22304.bc` (6.6M) | [#22304](https://github.com/curl/curl/pull/22304) | fix event-based connection shutdown and add a test for it | lib/cfilters.c, lib/connect.c, lib/connect.h, lib/cshutdn.c, |
| `pr-22309.bc` (6.6M) | [#22309](https://github.com/curl/curl/pull/22309) | setopt: reject CR and LF octets in curl_slists given to options | lib/setopt.c, src/config2setopts.c, tests/libtest/lib2017.c |
| `pr-22310.bc` (6.6M) | [#22310](https://github.com/curl/curl/pull/22310) | rtsp: reject control bytes in stream URI, transport and session ID | lib/rtsp.c, tests/libtest/lib657.c |
| `pr-22313.bc` (6.6M) | [#22313](https://github.com/curl/curl/pull/22313) | urlapi: allow URLs to have no userauth (hostname) | lib/urlapi.c, tests/libtest/lib1560.c |
| `pr-22315.bc` (6.6M) | [#22315](https://github.com/curl/curl/pull/22315) | tool_getparam: reject argument to options using CRLF | src/tool_getparam.c, src/tool_getparam.h |
| `pr-22317.bc` (6.6M) | [#22317](https://github.com/curl/curl/pull/22317) | ngtcp2: let verify failures win over expiry processing errors | lib/vquic/cf-ngtcp2-cmn.c |
| `pr-22322.bc` (6.6M) | [#22322](https://github.com/curl/curl/pull/22322) | mime.c: avoid integer overflow in base64 size calculation | lib/mime.c |
| `pr-22324.bc` (6.6M) | [#22324](https://github.com/curl/curl/pull/22324) | ssls: fix import leak | lib/vtls/vtls_scache.c, lib/vtls/vtls_scache.h, lib/vtls/vtl |
| `pr-22326.bc` (6.6M) | [#22326](https://github.com/curl/curl/pull/22326) | idn: restore `MultiByteToWideChar()` `MB_ERR_INVALID_CHARS` flag | lib/curlx/fopen.c, lib/curlx/multibyte.c, lib/idn.c, lib/vtl |
| `pr-22328.bc` (6.6M) | [#22328](https://github.com/curl/curl/pull/22328) | tool_cb_prg: avoid integer overflows | src/tool_cb_prg.c |
