# `bc/libssh2/` — libssh2 bitcode for fermat-check incremental-persist
This folder holds typed-pointer LLVM 15 bitcode for **libssh2**, used as the input for the `fermat-check` incremental-persist benchmark (`scripts/run_bench.sh`).
## Layout
- **`old.bc`** — the stored baseline. Produced from the upstream source at commit [`fe667c60`](https://github.com/libssh2/libssh2/commit/fe667c60). `run_bench.sh` stores SEGs from this once; everything else is benchmarked against it.
- **`pr-<NNNN>.bc`** — one bitcode per pull request. Each was produced by applying that PR's source onto the baseline commit and recompiling with the **identical** flags used for `old.bc`. (Names with `pr-syn<N>.bc` are synthetic no-op edits, not real PRs.)
## Build configuration
| | |
|---|---|
| Upstream | `libssh2/libssh2` (<https://github.com/libssh2/libssh2>)
| Baseline commit | `fe667c60`
| Artifact extracted | `libssh2.so.1.0.1 (shared lib, OpenSSL backend)`
| Toolchain | gllvm `gclang` + `get-bc`, LLVM 15, `-Xclang -no-opaque-pointers`
| Result size | `libssh2 (SSH client lib, ~moderate size)`
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
git clone https://github.com/libssh2/libssh2.git libssh2
cd libssh2
git checkout fe667c60

# build + extract bitcode (artifact: libssh2.so.1.0.1 (shared lib, OpenSSL backend))
cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DBUILD_SHARED_LIBS=ON -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF -DENABLE_ZLIB_COMPRESSION=OFF
get-bc -o old.bc
```
### 2. Build `pr-NNNN.bc` (one per pull request)
Reset to the baseline, apply the PR's source, rebuild with the **same** command, and save under a new name:
```bash
git reset --hard fe667c60
# fetch the PR ref and copy its changed .c/.h onto the tree
git fetch origin pull/NNNN/head:pr-NNNN
mb=$(git merge-base HEAD pr-NNNN)
git diff --name-only $mb pr-NNNN | grep -E '\.(c|h)$' | \
  while read f; do git show pr-NNNN:$f > $f; done
git branch -D pr-NNNN

# rebuild with the SAME command as step 1
cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DBUILD_SHARED_LIBS=ON -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF -DENABLE_ZLIB_COMPRESSION=OFF
get-bc -o pr-NNNN.bc
```
> `scripts/build_pr_bc.sh` automates steps 1-2 for every PR recorded in `results/<proj>/summary.tsv`; run it from the repo root: `./scripts/build_pr_bc.sh libssh2`.
See [`docs/producing-bitcode.md`](../../docs/producing-bitcode.md) for the full recipe.
## Reproduce the results (fermat-check analysis)
Three explicit `fermat-check` invocations reproduce one data point: **store** the baseline once, then run a sample **incremental** (reuses stored SEGs) and **scratch** (no store) to compare.
```bash
CBC=$HOME/github/FermatAnalyzer/build/tools/fermat-check/fermat-check

# 1) store the baseline once (writes ./persist/libssh2/seg/ ...)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -serialize-seg -store-models-dir=./persist/libssh2 bc/libssh2/old.bc

# 2) incremental on a PR's bitcode (loads clean SEGs, rebuilds dirty)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -enable-incremental-persist -store-models-dir=./persist/libssh2 bc/libssh2/pr-NNNN.bc

# 3) scratch on the same bitcode (no store; full rebuild)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only bc/libssh2/pr-NNNN.bc
```
Run steps 2–3 for each `pr-*.bc` in this folder. Compare the `SEG-Building spends time ***...***` line and the `[Incremental persist] body-dirty: N, +callers: M` line. Incremental wins when `inc` wall-time < `scratch` wall-time.
Result columns and log fields are explained in [`../../docs/fermat-check-incremental-persist.md`](../../docs/fermat-check-incremental-persist.md) and [`../../README.md`](../../README.md#result-columns).
## Files in this folder (9 total)
| File | PR / source | Title | Changed C/C++ files |
|------|-------------|-------|---------------------|
| `old.bc` (1.7M) | baseline `fe667c60` | — | — |
| `pr-1758.bc` (1.7M) | [#1758](https://github.com/libssh2/libssh2/pull/1758) | Fix mbedTLS AES-CBC backend: avoid BAD_INPUT_DATA during cipher_finish | src/mbedtls.c |
| `pr-2052.bc` (1.7M) | [#2052](https://github.com/libssh2/libssh2/pull/2052) | transport.c: Additional boundary checks for packet length | src/transport.c |
| `pr-2067.bc` (1.7M) | [#2067](https://github.com/libssh2/libssh2/pull/2067) | sftp.c: Replace LIBSSH2_ERROR_BUFFER_TOO_SMALL with LIBSSH2_ERROR_PROT | src/sftp.c |
| `pr-2127.bc` (1.7M) | [#2127](https://github.com/libssh2/libssh2/pull/2127) | publickey: fix potential arbitrary free in `libssh2_publickey_list_fet | src/publickey.c |
| `pr-2133.bc` (1.7M) | [#2133](https://github.com/libssh2/libssh2/pull/2133) | sftp: cap readdir response size and fix window adjust overflow | src/sftp.c |
| `pr-2140.bc` (1.7M) | [#2140](https://github.com/libssh2/libssh2/pull/2140) | channel.c: Check open_data length before accessing reason_code | src/channel.c |
| `pr-2170.bc` (1.7M) | [#2170](https://github.com/libssh2/libssh2/pull/2170) | sftp.c: correctly size packet length when using attrs_in | src/sftp.c |
| `pr-2180.bc` (1.7M) | [#2180](https://github.com/libssh2/libssh2/pull/2180) | Prevent dangling pointer by nullifying data | src/sftp.c |
