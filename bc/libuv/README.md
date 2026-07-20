# `bc/libuv/` — libuv bitcode for cb-check incremental-persist
This folder holds typed-pointer LLVM 15 bitcode for **libuv**, used as the input for the `cb-check` incremental-persist benchmark (`scripts/run_bench.sh`).
## Layout
- **`old.bc`** — the stored baseline. Produced from the upstream source at commit [`2cadaa40`](https://github.com/libuv/libuv/commit/2cadaa40). `run_bench.sh` stores SEGs from this once; everything else is benchmarked against it.
- **`pr-<NNNN>.bc`** — one bitcode per pull request. Each was produced by applying that PR's source onto the baseline commit and recompiling with the **identical** flags used for `old.bc`. (Names with `pr-syn<N>.bc` are synthetic no-op edits, not real PRs.)
## Build configuration
| | |
|---|---|
| Upstream | `libuv/libuv` (<https://github.com/libuv/libuv>)
| Baseline commit | `2cadaa40`
| Artifact extracted | `libuv.so.1.0.0 (shared lib)`
| Toolchain | gllvm `gclang` + `get-bc`, LLVM 15, `-Xclang -no-opaque-pointers`
| Result size | `libuv (~50k inst)`
```bash
# how each .bc was built (same for old.bc and every pr-*.bc)
cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=OFF
get-bc -o <file>.bc <artifact>
```
See [`docs/producing-bitcode.md`](../../docs/producing-bitcode.md) for the full recipe.
## Reproduce the results
Three explicit `cb-check` invocations reproduce one data point: **store** the baseline once, then run a sample **incremental** (reuses stored SEGs) and **scratch** (no store) to compare.
```bash
CBC=$HOME/github/FermatAnalyzer/build/tools/cb-check/cb-check

# 1) store the baseline once (writes ./persist/libuv/seg/ ...)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -persist-dir=./persist/libuv bc/libuv/old.bc

# 2) incremental on a PR's bitcode (loads clean SEGs, rebuilds dirty)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -enable-incremental-persist -persist-dir=./persist/libuv bc/libuv/pr-NNNN.bc

# 3) scratch on the same bitcode (no store; full rebuild)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only bc/libuv/pr-NNNN.bc
```
Run steps 2–3 for each `pr-*.bc` in this folder. Compare the `SEG-Building spends time ***...***` line and the `[Incremental persist] body-dirty: N, +callers: M` line. Incremental wins when `inc` wall-time < `scratch` wall-time.
Result columns and log fields are explained in [`../../docs/cb-check-incremental-persist.md`](../../docs/cb-check-incremental-persist.md) and [`../../README.md`](../../README.md#result-columns).
## Files in this folder (21 total)
| File | PR / source | Title | Changed C/C++ files |
|------|-------------|-------|---------------------|
| `old.bc` (1.3M) | baseline `2cadaa40` | — | — |
| `pr-5157.bc` (1.3M) | [#5157](https://github.com/libuv/libuv/pull/5157) | unix: restore prior signal disposition on stop | src/unix/signal.c, test/test-list.h, test/test-signal.c |
| `pr-5158.bc` (1.3M) | [#5158](https://github.com/libuv/libuv/pull/5158) | win,process: skip dump silently if no valid folder can be determined | src/win/process.c |
| `pr-5159.bc` (1.3M) | [#5159](https://github.com/libuv/libuv/pull/5159) | win: replace monotonicity assertion in 'uv_update_time' for time-clamp | src/win/core.c |
| `pr-5160.bc` (1.3M) | [#5160](https://github.com/libuv/libuv/pull/5160) | win,unix: add uv_pipe_open_ex | include/uv.h, src/unix/pipe.c, src/win/pipe.c, test/test-lis |
| `pr-5163.bc` (1.3M) | [#5163](https://github.com/libuv/libuv/pull/5163) | unix,udp: handle msg_hdr.msg_namelen=0 on recvmmsg | src/unix/udp.c, test/test-list.h, test/test-udp-mmsg.c |
| `pr-5165.bc` (1.3M) | [#5165](https://github.com/libuv/libuv/pull/5165) | unix: drain tty reads on POLLHUP without POLLIN | src/unix/stream.c, test/test-tty.c |
| `pr-5170.bc` (1.3M) | [#5170](https://github.com/libuv/libuv/pull/5170) | a few changes from httpuv | src/unix/core.c, src/win/fs.c, src/win/snprintf.c, src/win/w |
| `pr-5173.bc` (1.3M) | [#5173](https://github.com/libuv/libuv/pull/5173) | tcp,pipe: add uv_tcp_accept_raw/uv_pipe_accept_raw for zero-copy cross | include/uv.h, src/unix/pipe.c, src/unix/tcp.c, src/win/pipe. |
| `pr-5174.bc` (1.3M) | [#5174](https://github.com/libuv/libuv/pull/5174) | unix: return EINVAL for invalid tty modes | src/unix/tty.c, test/test-tty.c |
| `pr-5177.bc` (1.3M) | [#5177](https://github.com/libuv/libuv/pull/5177) | unix: fix UV_FS_O_DIRECT on more Linux architectures | include/uv/unix.h |
| `pr-5179.bc` (1.3M) | [#5179](https://github.com/libuv/libuv/pull/5179) | win: fix use of wrong constant in tcp code | src/win/tcp.c, src/win/winapi.h |
| `pr-5180.bc` (1.3M) | [#5180](https://github.com/libuv/libuv/pull/5180) | doc: add UB warning to threading documentation | test/test-thread-priority.c |
| `pr-5181.bc` (1.3M) | [#5181](https://github.com/libuv/libuv/pull/5181) | win: fix unique named pipes to work inside Windows AppContainer | src/win/pipe.c, test/appcontainer.c, test/task.h, test/test- |
| `pr-5186.bc` (1.3M) | [#5186](https://github.com/libuv/libuv/pull/5186) | unix,poll: fix callback event bits on error/hangup | src/unix/poll.c |
| `pr-5187.bc` (1.3M) | [#5187](https://github.com/libuv/libuv/pull/5187) | sunos: use getrandom(2) for uv_random | src/random.c |
| `pr-5188.bc` (1.3M) | [#5188](https://github.com/libuv/libuv/pull/5188) | unix: handle trailing empty write buffers | src/unix/stream.c, test/test-list.h, test/test-pipe-write.c |
| `pr-5189.bc` (1.3M) | [#5189](https://github.com/libuv/libuv/pull/5189) | linux: synthesize events for always-ready fds | src/unix/linux.c, test/test-list.h, test/test-pipe-dev-null. |
| `pr-5191.bc` (1.3M) | [#5191](https://github.com/libuv/libuv/pull/5191) | Haiku: build tests with libbsd | test/test-tty.c |
| `pr-5192.bc` (1.3M) | [#5192](https://github.com/libuv/libuv/pull/5192) | unix: fix static declaration in nested block for AIX and IBM i PASE | src/unix/async.c |
| `pr-5193.bc` (1.3M) | [#5193](https://github.com/libuv/libuv/pull/5193) | udp: re-connect a connected handle in place | src/uv-common.c, test/test-udp-connect.c, test/test-udp-conn |
