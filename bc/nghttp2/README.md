# `bc/nghttp2/` — nghttp2 bitcode for fermat-check incremental-persist
This folder holds typed-pointer LLVM 15 bitcode for **nghttp2**, used as the input for the `fermat-check` incremental-persist benchmark (`scripts/run_bench.sh`).
## Layout
- **`old.bc`** — the stored baseline. Produced from the upstream source at commit [`d5ab3d92`](https://github.com/nghttp2/nghttp2/commit/d5ab3d92). `run_bench.sh` stores SEGs from this once; everything else is benchmarked against it.
- **`pr-<NNNN>.bc`** — one bitcode per pull request. Each was produced by applying that PR's source onto the baseline commit and recompiling with the **identical** flags used for `old.bc`. (Names with `pr-syn<N>.bc` are synthetic no-op edits, not real PRs.)
## Build configuration
| | |
|---|---|
| Upstream | `nghttp2/nghttp2` (<https://github.com/nghttp2/nghttp2>)
| Baseline commit | `d5ab3d92`
| Artifact extracted | `libnghttp2.so.14.29.4 (shared lib)`
| Toolchain | gllvm `gclang` + `get-bc`, LLVM 15, `-Xclang -no-opaque-pointers`
| Result size | `libnghttp2 (~small HTTP/2 lib)`
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
git clone https://github.com/nghttp2/nghttp2.git nghttp2
cd nghttp2
git checkout d5ab3d92

# project-specific setup
git submodule update --init --recursive

# build + extract bitcode (artifact: libnghttp2.so.14.29.4 (shared lib))
cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DBUILD_STATIC_LIBS=OFF -DENABLE_APP=OFF -DENABLE_HPACK_TOOLS=OFF -DENABLE_EXAMPLES=OFF
get-bc -o old.bc
```
### 2. Build `pr-NNNN.bc` (one per pull request)
Reset to the baseline, apply the PR's source, rebuild with the **same** command, and save under a new name:
```bash
git reset --hard d5ab3d92
# fetch the PR ref and copy its changed .c/.h onto the tree
git fetch origin pull/NNNN/head:pr-NNNN
mb=$(git merge-base HEAD pr-NNNN)
git diff --name-only $mb pr-NNNN | grep -E '\.(c|h)$' | \
  while read f; do git show pr-NNNN:$f > $f; done
git branch -D pr-NNNN

# rebuild with the SAME command as step 1
cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DBUILD_STATIC_LIBS=OFF -DENABLE_APP=OFF -DENABLE_HPACK_TOOLS=OFF -DENABLE_EXAMPLES=OFF
get-bc -o pr-NNNN.bc
```
> `scripts/build_pr_bc.sh` automates steps 1-2 for every PR recorded in `results/<proj>/summary.tsv`; run it from the repo root: `./scripts/build_pr_bc.sh nghttp2`.
See [`docs/producing-bitcode.md`](../../docs/producing-bitcode.md) for the full recipe.
## Reproduce the results (fermat-check analysis)
Three explicit `fermat-check` invocations reproduce one data point: **store** the baseline once, then run a sample **incremental** (reuses stored SEGs) and **scratch** (no store) to compare.
```bash
CBC=$HOME/github/FermatAnalyzer/build/tools/fermat-check/fermat-check

# 1) store the baseline once (-serialize-seg → ./persist/nghttp2/<module>/SEG/*.json)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -serialize-seg -store-models-dir=./persist/nghttp2 bc/nghttp2/old.bc

# 2) incremental on a PR's bitcode (loads clean SEGs, rebuilds dirty)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -enable-incremental-persist -store-models-dir=./persist/nghttp2 bc/nghttp2/pr-NNNN.bc

# 3) scratch on the same bitcode (no store; full rebuild)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only bc/nghttp2/pr-NNNN.bc
```
Run steps 2–3 for each `pr-*.bc` in this folder. Compare the `SEG-Building spends time ***...***` line and the `[Incremental persist] body-dirty: N, +callers: M` line. Incremental wins when `inc` wall-time < `scratch` wall-time.
Result columns and log fields are explained in [`../../docs/fermat-check-incremental-persist.md`](../../docs/fermat-check-incremental-persist.md) and [`../../README.md`](../../README.md#result-columns).
## Files in this folder (9 total)
| File | PR / source | Title | Changed C/C++ files |
|------|-------------|-------|---------------------|
| `old.bc` (1004K) | baseline `d5ab3d92` | — | — |
| `pr-2780.bc` (1004K) | [#2780](https://github.com/nghttp2/nghttp2/pull/2780) | net: Use macros for win32 hton*/ntoh* fallbacks | lib/nghttp2_net.h |
| `pr-2783.bc` (1004K) | [#2783](https://github.com/nghttp2/nghttp2/pull/2783) | Bump sfparse | lib/sfparse.c, lib/sfparse.h |
| `pr-2784.bc` (1004K) | [#2784](https://github.com/nghttp2/nghttp2/pull/2784) | helper: Initialize array with designated initializers | lib/nghttp2_helper.c |
| `pr-2785.bc` (1004K) | [#2785](https://github.com/nghttp2/nghttp2/pull/2785) | Reformat downcase table | lib/nghttp2_helper.c |
| `pr-2787.bc` (1004K) | [#2787](https://github.com/nghttp2/nghttp2/pull/2787) | Upper case hex integer literals in huffman data table | lib/nghttp2_hd_huffman_data.c |
| `pr-2788.bc` (1004K) | [#2788](https://github.com/nghttp2/nghttp2/pull/2788) | Upcase hex | lib/includes/nghttp2/nghttp2.h, lib/nghttp2_hd.c, lib/nghttp |
| `pr-2791.bc` (1004K) | [#2791](https://github.com/nghttp2/nghttp2/pull/2791) | Reformat huffman data table | lib/nghttp2_hd_huffman_data.c |
| `pr-2813.bc` (1004K) | [#2813](https://github.com/nghttp2/nghttp2/pull/2813) | Add the missing header value check for priority header field | lib/nghttp2_http.c, lib/nghttp2_http.h, tests/nghttp2_http_t |
