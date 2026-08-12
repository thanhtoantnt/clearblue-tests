# `bc/mbedtls/` — mbedtls bitcode for fermat-check incremental-persist
This folder holds typed-pointer LLVM 15 bitcode for **mbedtls**, used as the input for the `fermat-check` incremental-persist benchmark (`scripts/run_bench.sh`).
## Layout
- **`old.bc`** — the stored baseline. Produced from the upstream source at commit [`12556bc2a2`](https://github.com/Mbed-TLS/mbedtls/commit/12556bc2a2). `run_bench.sh` stores SEGs from this once; everything else is benchmarked against it.
- **`pr-<NNNN>.bc`** — one bitcode per pull request. Each was produced by applying that PR's source onto the baseline commit and recompiling with the **identical** flags used for `old.bc`. (Names with `pr-syn<N>.bc` are synthetic no-op edits, not real PRs.)
## Build configuration
| | |
|---|---|
| Upstream | `Mbed-TLS/mbedtls` (<https://github.com/Mbed-TLS/mbedtls>)
| Baseline commit | `12556bc2a2`
| Artifact extracted | `libmbedtls.so.4.2.0 (shared lib)`
| Toolchain | gllvm `gclang` + `get-bc`, LLVM 15, `-Xclang -no-opaque-pointers`
| Result size | `libmbedtls (~25k inst)`
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
git clone https://github.com/Mbed-TLS/mbedtls.git mbedtls
cd mbedtls
git checkout 12556bc2a2

# project-specific setup
git submodule update --init --recursive && pip install jsonschema jinja2

# build + extract bitcode (artifact: libmbedtls.so.4.2.0 (shared lib))
cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DENABLE_PROGRAMS=OFF -DENABLE_TESTING=OFF -DUSE_SHARED_MBEDTLS_LIBRARY=ON
get-bc -o old.bc
```
### 2. Build `pr-NNNN.bc` (one per pull request)
Reset to the baseline, apply the PR's source, rebuild with the **same** command, and save under a new name:
```bash
git reset --hard 12556bc2a2
# fetch the PR ref and copy its changed .c/.h onto the tree
git fetch origin pull/NNNN/head:pr-NNNN
mb=$(git merge-base HEAD pr-NNNN)
git diff --name-only $mb pr-NNNN | grep -E '\.(c|h)$' | \
  while read f; do git show pr-NNNN:$f > $f; done
git branch -D pr-NNNN

# rebuild with the SAME command as step 1
cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DENABLE_PROGRAMS=OFF -DENABLE_TESTING=OFF -DUSE_SHARED_MBEDTLS_LIBRARY=ON
get-bc -o pr-NNNN.bc
```
> `scripts/build_pr_bc.sh` automates steps 1-2 for every PR recorded in `results/<proj>/summary.tsv`; run it from the repo root: `./scripts/build_pr_bc.sh mbedtls`.
See [`docs/producing-bitcode.md`](../../docs/producing-bitcode.md) for the full recipe.
## Reproduce the results (fermat-check analysis)
Three explicit `fermat-check` invocations reproduce one data point: **store** the baseline once, then run a sample **incremental** (reuses stored SEGs) and **scratch** (no store) to compare.
```bash
CBC=$HOME/github/FermatAnalyzer/build/tools/fermat-check/fermat-check

# 1) store the baseline once (-serialize-seg → ./persist/mbedtls/<module>/SEG/*.json)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -serialize-seg -store-models-dir=./persist/mbedtls bc/mbedtls/old.bc

# 2) incremental on a PR's bitcode (loads clean SEGs, rebuilds dirty)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -enable-incremental-persist -store-models-dir=./persist/mbedtls bc/mbedtls/pr-NNNN.bc

# 3) scratch on the same bitcode (no store; full rebuild)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only bc/mbedtls/pr-NNNN.bc
```
Run steps 2–3 for each `pr-*.bc` in this folder. Compare the `SEG-Building spends time ***...***` line and the `[Incremental persist] body-dirty: N, +callers: M` line. Incremental wins when `inc` wall-time < `scratch` wall-time.
Result columns and log fields are explained in [`../../docs/fermat-check-incremental-persist.md`](../../docs/fermat-check-incremental-persist.md) and [`../../README.md`](../../README.md#result-columns).
## Files in this folder (10 total)
| File | PR / source | Title | Changed C/C++ files |
|------|-------------|-------|---------------------|
| `old.bc` (1.6M) | baseline `12556bc2a2` | — | — |
| `pr-10816.bc` (1.6M) | [#10816](https://github.com/Mbed-TLS/mbedtls/pull/10816) | Mbedtls 4.1.1 mergeback | doxygen/input/doc_mainpage.h, include/mbedtls/build_info.h,  |
| `pr-10819.bc` (1.6M) | [#10819](https://github.com/Mbed-TLS/mbedtls/pull/10819) | fix issue with sprintf's unguarded by MBEDTLS_X509_REMOVE_INFO | include/mbedtls/oid.h, include/mbedtls/x509.h, library/ssl_t |
| `pr-10824.bc` (1.6M) | [#10824](https://github.com/Mbed-TLS/mbedtls/pull/10824) | Fix x509_get_uid() accepting constructed [1]/[2] tags | library/x509_crt.c |
| `pr-10825.bc` (1.6M) | [#10825](https://github.com/Mbed-TLS/mbedtls/pull/10825) | Reject empty ALPN protocol list in mbedtls_ssl_conf_alpn_protocols() | library/ssl_tls.c |
| `pr-10826.bc` (1.6M) | [#10826](https://github.com/Mbed-TLS/mbedtls/pull/10826) | Reject zero-length serial number in mbedtls_x509write_crt | include/mbedtls/x509_crt.h, library/x509write_crt.c |
| `pr-10827.bc` (1.6M) | [#10827](https://github.com/Mbed-TLS/mbedtls/pull/10827) | Fix x509_get_entries() not validating CRL entry's own SEQUENCE length  | library/x509_crl.c |
| `pr-10829.bc` (1.6M) | [#10829](https://github.com/Mbed-TLS/mbedtls/pull/10829) | Fix memory errors in sample programs | programs/ssl/ssl_context_info.c, programs/ssl/ssl_server2.c |
| `pr-10831.bc` (1.6M) | [#10831](https://github.com/Mbed-TLS/mbedtls/pull/10831) | Add input length validation in dummy_ticket_parse() | programs/ssl/ssl_server2.c |
| `pr-10833.bc` (1.6M) | [#10833](https://github.com/Mbed-TLS/mbedtls/pull/10833) | Fix off-by-one over-read in TLS 1.2 ClientHello and CertificateRequest | library/ssl_tls12_client.c, library/ssl_tls12_server.c |
