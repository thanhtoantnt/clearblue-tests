# `bc/rnp/` — rnp bitcode for fermat-check incremental-persist
This folder holds typed-pointer LLVM 15 bitcode for **rnp**, used as the input for the `fermat-check` incremental-persist benchmark (`scripts/run_bench.sh`).
## Layout
- **`old.bc`** — the stored baseline. Produced from the upstream source at commit [`aad1892e`](https://github.com/rnpgp/rnp/commit/aad1892e) (`v0.18.1`). `run_bench.sh` stores SEGs from this once; everything else is benchmarked against it.
- **`pr-<NNNN>.bc`** — one bitcode per pull request. Each was produced by applying that PR's source onto the baseline commit and recompiling with the **identical** flags used for `old.bc`. (Names with `pr-syn<N>.bc` are synthetic no-op edits, not real PRs.)
## Build configuration
| | |
|---|---|
| Upstream | `rnpgp/rnp` (<https://github.com/rnpgp/rnp>)
| Baseline commit | `aad1892e` (`v0.18.1`)
| Artifact extracted | `rnp` (CLI binary; links `src/rnp/rnpcfg.cpp`)
| Toolchain | gllvm `gclang` / `gclang++` + `get-bc`, LLVM 15, `-Xclang -no-opaque-pointers`
| Result size | `rnp CLI (C++ unordered_map operator[] stores; size not measured)`
## Case
`src/rnp/rnpcfg.cpp` stores a heap pointer into a `std::unordered_map` through `operator[]`. The map keeps the pointer; `clear()` / `unset()` `delete` it. On FermatAnalyzer `main`, `-ps-ml` reports those `new`s as leaks because the store address is `unordered_map::operator[]`. That is the false positive in [FermatAnalyzer#206](https://github.com/fermat-hkrc/FermatAnalyzer/pull/206). This file does not assign through `.at()`.

| function | line | store |
|---|---:|---|
| `rnp_cfg::set_str` | 148, 155 | `vals_[key] = new rnp_cfg_str_val(val)` |
| `rnp_cfg::set_int` | 162 | `vals_[key] = new rnp_cfg_int_val(val)` |
| `rnp_cfg::set_bool` | 169 | `vals_[key] = new rnp_cfg_bool_val(val)` |
| `rnp_cfg::add_str` | 186 | `vals_[key] = new rnp_cfg_list_val()` |
| `rnp_cfg::copy` | 470 | `vals_[it.first] = val` (`val` is a `new` above) |

`vals_` is `std::unordered_map<std::string, rnp_cfg_val *>` (`src/rnp/rnpcfg.h`). Extract the `rnp` CLI, not `librnp`: `rnpcfg.cpp` is not in the library.
## Reproduce the .bc files from source
The committed `.bc` files are self-contained, but you can rebuild any of them from the upstream source. The key rule: **`old.bc` and every `pr-*.bc` must use the identical toolchain and flags** so `fermat-check` fingerprints match.
### Prerequisites (once)
```bash
# gllvm wraps clang to embed bitcode -- https://github.com/SRI-CSL/gllvm
go install github.com/SRI-CSL/gllvm/cmd/gclang@latest
go install github.com/SRI-CSL/gllvm/cmd/gclang++@latest
go install github.com/SRI-CSL/gllvm/cmd/get-bc@latest
# point gllvm at LLVM 15 (typed pointers), then put it on PATH
export LLVM_COMPILER_PATH=$HOME/tools/llvm15-official/bin
export PATH=$HOME/go/bin:$LLVM_COMPILER_PATH:$PATH
which gclang gclang++ get-bc   # sanity check
sudo apt-get install -y cmake ninja-build libssl-dev zlib1g-dev libbz2-dev libjson-c-dev
```
### 1. Build `old.bc` (the baseline)
```bash
git clone https://github.com/rnpgp/rnp.git rnp
cd rnp
git checkout aad1892e

# project-specific setup
# apt: cmake ninja-build libssl-dev zlib1g-dev libbz2-dev libjson-c-dev
# also: go install github.com/SRI-CSL/gllvm/cmd/gclang++@latest

# build + extract bitcode (artifact: rnp (CLI binary; links src/rnp/rnpcfg.cpp))
cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_CXX_COMPILER=gclang++ -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_CXX_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DBUILD_SHARED_LIBS=ON -DBUILD_TESTING=OFF -DENABLE_DOC=OFF -DDOWNLOAD_GTEST=OFF -DCRYPTO_BACKEND=openssl && ninja rnp
get-bc -o old.bc src/rnp/rnp
```
### 2. Build `pr-NNNN.bc` (one per pull request)
Reset to the baseline, apply the PR's source, rebuild with the **same** command, and save under a new name:
```bash
git reset --hard aad1892e
# fetch the PR ref and copy its changed .c/.h/.cpp onto the tree
git fetch origin pull/NNNN/head:pr-NNNN
mb=$(git merge-base HEAD pr-NNNN)
git diff --name-only $mb pr-NNNN | grep -E '\.(c|h|cc|cpp)$' | \
  while read f; do git show pr-NNNN:$f > $f; done
git branch -D pr-NNNN

# rebuild with the SAME command as step 1
cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_CXX_COMPILER=gclang++ -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_CXX_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DBUILD_SHARED_LIBS=ON -DBUILD_TESTING=OFF -DENABLE_DOC=OFF -DDOWNLOAD_GTEST=OFF -DCRYPTO_BACKEND=openssl && ninja rnp
get-bc -o pr-NNNN.bc src/rnp/rnp
```
> `scripts/build_pr_bc.sh` automates steps 1-2 for every PR recorded in `results/<proj>/summary.tsv`; run it from the repo root: `./scripts/build_pr_bc.sh rnp`.
See [`docs/producing-bitcode.md`](../../docs/producing-bitcode.md) for the full recipe.
## Reproduce the results (fermat-check analysis)
Three explicit `fermat-check` invocations reproduce one data point: **store** the baseline once, then run a sample **incremental** (reuses stored SEGs) and **scratch** (no store) to compare.
```bash
CBC=$HOME/github/FermatAnalyzer/build/tools/fermat-check/fermat-check

# 1) store the baseline once (-serialize-seg → ./persist/rnp/<module>/SEG/*.json)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -serialize-seg -store-models-dir=./persist/rnp bc/rnp/old.bc

# 2) incremental on a PR's bitcode (loads clean SEGs, rebuilds dirty)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -enable-incremental-persist -store-models-dir=./persist/rnp bc/rnp/pr-NNNN.bc

# 3) scratch on the same bitcode (no store; full rebuild)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only bc/rnp/pr-NNNN.bc
```
Run steps 2–3 for each `pr-*.bc` in this folder. Compare the `SEG-Building spends time ***...***` line and the `[Incremental persist] body-dirty: N, +callers: M` line. Incremental wins when `inc` wall-time < `scratch` wall-time.
Result columns and log fields are explained in [`../../docs/fermat-check-incremental-persist.md`](../../docs/fermat-check-incremental-persist.md) and [`../../README.md`](../../README.md#result-columns).
## Files in this folder
| File | PR / source | Title | Changed C/C++ files |
|------|-------------|-------|---------------------|
| `old.bc` | baseline `aad1892e` | — | — |
