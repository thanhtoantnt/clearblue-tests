# `bc/zstd/` — zstd bitcode for fermat-check incremental-persist
This folder holds typed-pointer LLVM 15 bitcode for **zstd**, used as the input for the `fermat-check` incremental-persist benchmark (`scripts/run_bench.sh`).
## Layout
- **`old.bc`** — the stored baseline. Produced from the upstream source at commit [`5c7b7bad`](https://github.com/facebook/zstd/commit/5c7b7bad). `run_bench.sh` stores SEGs from this once; everything else is benchmarked against it.
- **`pr-<NNNN>.bc`** — one bitcode per pull request. Each was produced by applying that PR's source onto the baseline commit and recompiling with the **identical** flags used for `old.bc`. (Names with `pr-syn<N>.bc` are synthetic no-op edits, not real PRs.)
## Build configuration
| | |
|---|---|
| Upstream | `facebook/zstd` (<https://github.com/facebook/zstd>)
| Baseline commit | `5c7b7bad`
| Artifact extracted | `libzstd.so.1.6.0 (multithreaded shared lib)`
| Toolchain | gllvm `gclang` + `get-bc`, LLVM 15, `-Xclang -no-opaque-pointers`
| Result size | `libzstd (mt, ~300k inst)`
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
git clone https://github.com/facebook/zstd.git zstd
cd zstd
git checkout 5c7b7bad

# build + extract bitcode (artifact: libzstd.so.1.6.0 (multithreaded shared lib))
make -C lib lib-mt CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers'
get-bc -o old.bc
```
### 2. Build `pr-NNNN.bc` (one per pull request)
Reset to the baseline, apply the PR's source, rebuild with the **same** command, and save under a new name:
```bash
git reset --hard 5c7b7bad
# fetch the PR ref and copy its changed .c/.h onto the tree
git fetch origin pull/NNNN/head:pr-NNNN
mb=$(git merge-base HEAD pr-NNNN)
git diff --name-only $mb pr-NNNN | grep -E '\.(c|h)$' | \
  while read f; do git show pr-NNNN:$f > $f; done
git branch -D pr-NNNN

# rebuild with the SAME command as step 1
make -C lib lib-mt CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers'
get-bc -o pr-NNNN.bc
```
> `scripts/build_pr_bc.sh` automates steps 1-2 for every PR recorded in `results/<proj>/summary.tsv`; run it from the repo root: `./scripts/build_pr_bc.sh zstd`.
See [`docs/producing-bitcode.md`](../../docs/producing-bitcode.md) for the full recipe.
## Reproduce the results (fermat-check analysis)
Three explicit `fermat-check` invocations reproduce one data point: **store** the baseline once, then run a sample **incremental** (reuses stored SEGs) and **scratch** (no store) to compare.
```bash
CBC=$HOME/github/FermatAnalyzer/build/tools/fermat-check/fermat-check

# 1) store the baseline once (-serialize-seg → ./persist/zstd/<module>/SEG/*.json)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -serialize-seg -store-models-dir=./persist/zstd bc/zstd/old.bc

# 2) incremental on a PR's bitcode (loads clean SEGs, rebuilds dirty)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -enable-incremental-persist -store-models-dir=./persist/zstd bc/zstd/pr-NNNN.bc

# 3) scratch on the same bitcode (no store; full rebuild)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only bc/zstd/pr-NNNN.bc
```
Run steps 2–3 for each `pr-*.bc` in this folder. Compare the `SEG-Building spends time ***...***` line and the `[Incremental persist] body-dirty: N, +callers: M` line. Incremental wins when `inc` wall-time < `scratch` wall-time.
Result columns and log fields are explained in [`../../docs/fermat-check-incremental-persist.md`](../../docs/fermat-check-incremental-persist.md) and [`../../README.md`](../../README.md#result-columns).
## Files in this folder (13 total)
| File | PR / source | Title | Changed C/C++ files |
|------|-------------|-------|---------------------|
| `old.bc` (8.1M) | baseline `5c7b7bad` | — | — |
| `pr-4680.bc` (8.1M) | [#4680](https://github.com/facebook/zstd/pull/4680) | legacy/v0.1: fix truncating U32 cast in offset check; drop bogus point | lib/legacy/zstd_v01.c |
| `pr-4685.bc` (8.1M) | [#4685](https://github.com/facebook/zstd/pull/4685) | seekable: reject seek tables exceeding ZSTD_SEEKABLE_MAXFRAMES | contrib/seekable_format/zstdseek_decompress.c |
| `pr-4690.bc` (8.1M) | [#4690](https://github.com/facebook/zstd/pull/4690) | Fix size_t underflow in COVER_ctx_init for small training sets | lib/dictBuilder/cover.c, tests/fuzzer.c |
| `pr-4691.bc` (8.1M) | [#4691](https://github.com/facebook/zstd/pull/4691) | Fix hang on cyclic symlinks with -r -f | programs/util.c |
| `pr-4693.bc` (8.1M) | [#4693](https://github.com/facebook/zstd/pull/4693) | Fix COVER tiny training set underflow | lib/dictBuilder/cover.c, tests/fuzzer.c |
| `pr-4694.bc` (8.1M) | [#4694](https://github.com/facebook/zstd/pull/4694) | Use valid FSE dictionary costs in optimal parser | lib/compress/zstd_opt.c, tests/fuzzer.c |
| `pr-4695.bc` (8.1M) | [#4695](https://github.com/facebook/zstd/pull/4695) | Guard mirrored directory name allocation size | programs/util.c |
| `pr-4696.bc` (8.1M) | [#4696](https://github.com/facebook/zstd/pull/4696) | Document --max large-window decompression | programs/zstdcli.c |
| `pr-4700.bc` (8.1M) | [#4700](https://github.com/facebook/zstd/pull/4700) | Add --auto compression level | lib/compress/zstd_spectral_gap.c, lib/compress/zstd_spectral |
| `pr-4708.bc` (8.1M) | [#4708](https://github.com/facebook/zstd/pull/4708) | dibio: fix unsigned underflow in DiB_findMaxMem, guard nbSamples overf | programs/dibio.c |
| `pr-4710.bc` (8.1M) | [#4710](https://github.com/facebook/zstd/pull/4710) | Fix out-of-bounds read in FASTCOVER on small training samples | lib/dictBuilder/fastcover.c, tests/fuzzer.c |
| `pr-4711.bc` (8.1M) | [#4711](https://github.com/facebook/zstd/pull/4711) | Fix SVE2 histogram accumulator overflow | lib/compress/hist.c |
