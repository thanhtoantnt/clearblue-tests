# `bc/redis/` — redis bitcode for cb-check incremental-persist
This folder holds typed-pointer LLVM 15 bitcode for **redis**, used as the input for the `cb-check` incremental-persist benchmark (`scripts/run_bench.sh`).
## Layout
- **`old.bc`** — the stored baseline. Produced from the upstream source at commit [`1aa21f97d`](https://github.com/redis/redis/commit/1aa21f97d). `run_bench.sh` stores SEGs from this once; everything else is benchmarked against it.
- **`pr-<NNNN>.bc`** — one bitcode per pull request. Each was produced by applying that PR's source onto the baseline commit and recompiling with the **identical** flags used for `old.bc`. (Names with `pr-syn<N>.bc` are synthetic no-op edits, not real PRs.)
## Build configuration
| | |
|---|---|
| Upstream | `redis/redis` (<https://github.com/redis/redis>)
| Baseline commit | `1aa21f97d`
| Artifact extracted | `src/redis-server`
| Toolchain | gllvm `gclang` + `get-bc`, LLVM 15, `-Xclang -no-opaque-pointers`
| Result size | `redis-server (~540k inst)`
## Reproduce the .bc files from source
The committed `.bc` files are self-contained, but you can rebuild any of them from the upstream source. The key rule: **`old.bc` and every `pr-*.bc` must use the identical toolchain and flags** so `cb-check` fingerprints match.
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
git clone https://github.com/redis/redis.git redis
cd redis
git checkout 1aa21f97d

# build + extract bitcode (artifact: src/redis-server)
make CC=gclang OPTIMIZATION=-O0 CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers -fno-lto -Wno-error -std=gnu11' LDFLAGS=-fno-lto MALLOC=libc BUILD_TLS=no
get-bc -o old.bc
```
### 2. Build `pr-NNNN.bc` (one per pull request)
Reset to the baseline, apply the PR's source, rebuild with the **same** command, and save under a new name:
```bash
git reset --hard 1aa21f97d
# fetch the PR ref and copy its changed .c/.h onto the tree
git fetch origin pull/NNNN/head:pr-NNNN
mb=$(git merge-base HEAD pr-NNNN)
git diff --name-only $mb pr-NNNN | grep -E '\.(c|h)$' | \
  while read f; do git show pr-NNNN:$f > $f; done
git branch -D pr-NNNN

# rebuild with the SAME command as step 1
make CC=gclang OPTIMIZATION=-O0 CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers -fno-lto -Wno-error -std=gnu11' LDFLAGS=-fno-lto MALLOC=libc BUILD_TLS=no
get-bc -o pr-NNNN.bc
```
> `scripts/build_pr_bc.sh` automates steps 1-2 for every PR recorded in `results/<proj>/summary.tsv`; run it from the repo root: `./scripts/build_pr_bc.sh redis`.
See [`docs/producing-bitcode.md`](../../docs/producing-bitcode.md) for the full recipe.
## Reproduce the results (cb-check analysis)
Three explicit `cb-check` invocations reproduce one data point: **store** the baseline once, then run a sample **incremental** (reuses stored SEGs) and **scratch** (no store) to compare.
```bash
CBC=$HOME/github/FermatAnalyzer/build/tools/cb-check/cb-check

# 1) store the baseline once (writes ./persist/redis/seg/ ...)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -persist-dir=./persist/redis bc/redis/old.bc

# 2) incremental on a PR's bitcode (loads clean SEGs, rebuilds dirty)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -enable-incremental-persist -persist-dir=./persist/redis bc/redis/pr-NNNN.bc

# 3) scratch on the same bitcode (no store; full rebuild)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only bc/redis/pr-NNNN.bc
```
Run steps 2–3 for each `pr-*.bc` in this folder. Compare the `SEG-Building spends time ***...***` line and the `[Incremental persist] body-dirty: N, +callers: M` line. Incremental wins when `inc` wall-time < `scratch` wall-time.
Result columns and log fields are explained in [`../../docs/cb-check-incremental-persist.md`](../../docs/cb-check-incremental-persist.md) and [`../../README.md`](../../README.md#result-columns).
## Files in this folder (21 total)
| File | PR / source | Title | Changed C/C++ files |
|------|-------------|-------|---------------------|
| `old.bc` (15M) | baseline `1aa21f97d` | — | — |
| `pr-15408.bc` (15M) | [#15408](https://github.com/redis/redis/pull/15408) | Fix integer overflow on out-of-range numkeys | src/db.c |
| `pr-15409.bc` (15M) | [#15409](https://github.com/redis/redis/pull/15409) | Fix crash on CONFIG SET of TLS options in non-TLS builds | src/config.c |
| `pr-15412.bc` (15M) | [#15412](https://github.com/redis/redis/pull/15412) | Fix unit mismatch that disabled the FAST expire cycle stale trigger | src/expire.c |
| `pr-15418.bc` (15M) | [#15418](https://github.com/redis/redis/pull/15418) | Reject dupe fields when loading hash RDB payloads via RESTORE | src/rdb.c |
| `pr-15420.bc` (15M) | [#15420](https://github.com/redis/redis/pull/15420) | Avoid per-element SDS copies in SRANDMEMBER key <count> for hashtable  | src/t_set.c |
| `pr-15421.bc` (15M) | [#15421](https://github.com/redis/redis/pull/15421) | Avoid per-element SDS copies in ZRANDMEMBER key <count> CASE 3 (skipli | src/t_zset.c |
| `pr-15423.bc` (15M) | [#15423](https://github.com/redis/redis/pull/15423) | Reject malformed zset listpack payloads on untrusted RESTORE | src/rdb.c |
| `pr-15427.bc` (15M) | [#15427](https://github.com/redis/redis/pull/15427) | Fix activeExpireCycle starvation when a concurrent SCAN keeps the expi | src/expire.c |
| `pr-15433.bc` (15M) | [#15433](https://github.com/redis/redis/pull/15433) | Fix signed overflow in BITFIELD #offset parsing | src/bitops.c |
| `pr-15439.bc` (15M) | [#15439](https://github.com/redis/redis/pull/15439) | redis-benchmark: keep contended request counters off read-mostly cache | src/redis-benchmark.c |
| `pr-15440.bc` (15M) | [#15440](https://github.com/redis/redis/pull/15440) | kk | src/acl.c |
| `pr-15444.bc` (15M) | [#15444](https://github.com/redis/redis/pull/15444) | Add Redis core fuzzing scaffold | fuzz/fuzz_bitmap_commands.c, fuzz/fuzz_string_commands.c, fu |
| `pr-15446.bc` (15M) | [#15446](https://github.com/redis/redis/pull/15446) | Skip unready fds in select event backend | src/ae_select.c |
| `pr-15448.bc` (15M) | [#15448](https://github.com/redis/redis/pull/15448) | Fix/bio shutdown clean | bio.c, src/bio.c |
| `pr-15450.bc` (15M) | [#15450](https://github.com/redis/redis/pull/15450) | rdbLoadObject: create hash objects (HT/ListpackEx) directly during RDB | src/object.c, src/object.h, src/rdb.c |
| `pr-15453.bc` (15M) | [#15453](https://github.com/redis/redis/pull/15453) | Wake blocked list clients when SORT STORE overwrites a key | src/db.c |
| `pr-15455.bc` (15M) | [#15455](https://github.com/redis/redis/pull/15455) | Refactor duplicated array commands finalization logic | src/t_array.c |
| `pr-15457.bc` (15M) | [#15457](https://github.com/redis/redis/pull/15457) | fix: compare expire stale fraction to percent threshold correctly | src/expire.c |
| `pr-15460.bc` (15M) | [#15460](https://github.com/redis/redis/pull/15460) | redis-cli: header, index, auto percentiles and Ctrl-C summary for --la | src/redis-cli.c |
| `pr-15462.bc` (15M) | [#15462](https://github.com/redis/redis/pull/15462) | Fix dictMemUsage() over-counting no_value entries | src/dict.c |
