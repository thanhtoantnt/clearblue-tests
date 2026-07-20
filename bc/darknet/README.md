# `bc/darknet/` — darknet bitcode for cb-check incremental-persist
This folder holds typed-pointer LLVM 15 bitcode for **darknet**, used as the input for the `cb-check` incremental-persist benchmark (`scripts/run_bench.sh`).
## Layout
- **`old.bc`** — the stored baseline. Produced from the upstream source at commit [`f6afaabc`](https://github.com/pjreddie/darknet/commit/f6afaabc). `run_bench.sh` stores SEGs from this once; everything else is benchmarked against it.
- **`pr-<NNNN>.bc`** — one bitcode per pull request. Each was produced by applying that PR's source onto the baseline commit and recompiling with the **identical** flags used for `old.bc`. (Names with `pr-syn<N>.bc` are synthetic no-op edits, not real PRs.)
## Build configuration
| | |
|---|---|
| Upstream | `pjreddie/darknet` (<https://github.com/pjreddie/darknet>)
| Baseline commit | `f6afaabc`
| Artifact extracted | `darknet binary`
| Toolchain | gllvm `gclang` + `get-bc`, LLVM 15, `-Xclang -no-opaque-pointers`
| Result size | `darknet (~122k inst)`
```bash
# how each .bc was built (same for old.bc and every pr-*.bc)
make CC=gclang CPP=gclang++ DEBUG=1 GPU=0 CFLAGS='-Wall -Wno-unused-result -Wno-unknown-pragmas -Wfatal-errors -fPIC -O0 -g -Xclang -no-opaque-pointers'
get-bc -o <file>.bc <artifact>
```
See [`docs/producing-bitcode.md`](../../docs/producing-bitcode.md) for the full recipe.
## Reproduce the results
Three explicit `cb-check` invocations reproduce one data point: **store** the baseline once, then run a sample **incremental** (reuses stored SEGs) and **scratch** (no store) to compare.
```bash
CBC=$HOME/github/FermatAnalyzer/build/tools/cb-check/cb-check

# 1) store the baseline once (writes ./persist/darknet/seg/ ...)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -persist-dir=./persist/darknet bc/darknet/old.bc

# 2) incremental on a PR's bitcode (loads clean SEGs, rebuilds dirty)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -enable-incremental-persist -persist-dir=./persist/darknet bc/darknet/pr-NNNN.bc

# 3) scratch on the same bitcode (no store; full rebuild)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only bc/darknet/pr-NNNN.bc
```
Run steps 2–3 for each `pr-*.bc` in this folder. Compare the `SEG-Building spends time ***...***` line and the `[Incremental persist] body-dirty: N, +callers: M` line. Incremental wins when `inc` wall-time < `scratch` wall-time.
Result columns and log fields are explained in [`../../docs/cb-check-incremental-persist.md`](../../docs/cb-check-incremental-persist.md) and [`../../README.md`](../../README.md#result-columns).
## Files in this folder (19 total)
| File | PR / source | Title | Changed C/C++ files |
|------|-------------|-------|---------------------|
| `old.bc` (2.7M) | baseline `f6afaabc` | — | — |
| `pr-1996.bc` (2.7M) | [#1996](https://github.com/pjreddie/darknet/pull/1996) | fixed a bug while creating the dataset | src/image.c, src/image.h |
| `pr-2413.bc` (2.7M) | [#2413](https://github.com/pjreddie/darknet/pull/2413) | fix memory error in batchnorm layer | src/batchnorm_layer.c |
| `pr-2543.bc` (2.7M) | [#2543](https://github.com/pjreddie/darknet/pull/2543) | added comments | examples/voxel.c |
| `pr-2545.bc` (2.7M) | [#2545](https://github.com/pjreddie/darknet/pull/2545) | Compile with CUDNN 8+ | src/convolutional_layer.c |
| `pr-2614.bc` (2.7M) | [#2614](https://github.com/pjreddie/darknet/pull/2614) |  nightmare.c | examples/nightmare.c |
| `pr-2619.bc` (2.7M) | [#2619](https://github.com/pjreddie/darknet/pull/2619) | opencv4 support | src/image_opencv.cpp |
| `pr-2620.bc` (2.7M) | [#2620](https://github.com/pjreddie/darknet/pull/2620) | W openpose | openpose-darknet/openpose-darknet.cpp, openpose-darknet/run_ |
| `pr-2633.bc` (2.7M) | [#2633](https://github.com/pjreddie/darknet/pull/2633) | Fixed Missing 'nbiases' Item in YOLO Layer | src/yolo_layer.c |
| `pr-2657.bc` (2.7M) | [#2657](https://github.com/pjreddie/darknet/pull/2657) | Remove extra space blas.h | src/blas.h |
| `pr-syn0.bc` (2.7M) | synthetic touch #0 | *(no-op source edit)* | *(one .c file)* |
| `pr-syn1.bc` (2.7M) | synthetic touch #1 | *(no-op source edit)* | *(one .c file)* |
| `pr-syn2.bc` (2.7M) | synthetic touch #2 | *(no-op source edit)* | *(one .c file)* |
| `pr-syn3.bc` (2.7M) | synthetic touch #3 | *(no-op source edit)* | *(one .c file)* |
| `pr-syn4.bc` (2.7M) | synthetic touch #4 | *(no-op source edit)* | *(one .c file)* |
| `pr-syn5.bc` (2.7M) | synthetic touch #5 | *(no-op source edit)* | *(one .c file)* |
| `pr-syn6.bc` (2.7M) | synthetic touch #6 | *(no-op source edit)* | *(one .c file)* |
| `pr-syn7.bc` (2.7M) | synthetic touch #7 | *(no-op source edit)* | *(one .c file)* |
| `pr-syn8.bc` (2.7M) | synthetic touch #8 | *(no-op source edit)* | *(one .c file)* |
