# `bc/libjpeg-turbo/` — libjpeg-turbo bitcode for cb-check incremental-persist

This folder holds typed-pointer LLVM 15 bitcode for **libjpeg-turbo**, used as the
input for the `cb-check` incremental-persist benchmark (`scripts/run_bench.sh`).

## Layout

- **`old.bc`** — the stored baseline. Produced from the upstream source at tag
  [`3.2.0`](https://github.com/libjpeg-turbo/libjpeg-turbo/releases/tag/3.2.0)
  (`c85e6b90`). `run_bench.sh` stores SEGs from this once; everything else is
  benchmarked against it.
- **`pr-syn<N>.bc`** — synthetic single-function edits. Each inserts one
  `volatile` statement into the first function body of a distinct `src/*.c`
  file (so each data point marks **exactly one** function dirty — the ideal
  incremental case). Each produces distinct bitcode (md5-verified).

  | file | touched source |
  |------|----------------|
  | `pr-syn0.bc` | `src/jdatasrc.c` |
  | `pr-syn1.bc` | `src/jdcolor.c` |
  | `pr-syn2.bc` | `src/jccolor.c` |
  | `pr-syn3.bc` | `src/jchuff.c` |
  | `pr-syn4.bc` | `src/jdhuff.c` |
  | `pr-syn5.bc` | `src/jcmaster.c` |
  | `pr-syn6.bc` | `src/jdmaster.c` |
  | `pr-syn7.bc` | `src/jcparam.c` |

> libjpeg-turbo is a mature, low-PR-rate library, and its source moved into
> `src/` in recent releases, so the few historic merged PRs do not apply cleanly
> onto the `3.2.0` layout. The data points here are therefore **synthetic
> single-function edits** rather than real PRs — the same mechanism `libuv`/
> `darknet` use for their `syn<N>` rows. They give the cleanest incremental
> signal: one dirty function, ~927 reused.

## Build configuration

| | |
|---|---|
| Upstream | `libjpeg-turbo/libjpeg-turbo` (<https://github.com/libjpeg-turbo/libjpeg-turbo>)
| Baseline commit | `3.2.0` (`c85e6b90`)
| Artifact extracted | `libjpeg.so.62.4.0` (shared lib, ~928 functions / 928 SEGs)
| Toolchain | gllvm `gclang` + `getbc-link`, LLVM 15, `-Xclang -no-opaque-pointers`
| SIMD | **OFF** (`-DENABLE_SIMD=OFF`) — avoids NASM, keeps the build pure-C/portable
| Result size | `old.bc` ~4.2 MB

## Reproduce the `.bc` files from source

The committed `.bc` files are self-contained, but you can rebuild any of them
from the upstream source. The key rule: **`old.bc` and every `pr-*.bc` must use
the identical toolchain and flags** so `cb-check` fingerprints match.

### Prerequisites (once)

```bash
# gllvm wraps clang to embed bitcode -- https://github.com/SRI-CSL/gllvm
go install github.com/SRI-CSL/gllvm/cmd/gclang@latest
export LLVM_COMPILER_PATH=$HOME/tools/llvm15-official/bin
export PATH=$HOME/go/bin:$LLVM_COMPILER_PATH:$PATH
which gclang   # sanity check
```

> **Note on `get-bc`:** gllvm's `get-bc` reads the `.llvm_bc` sidecar paths from
> the artifact and `llvm-link`s them. On this host `get-bc` no longer classifies
> files after the system binutils wipe; use the drop-in helper
> `$HOME/bin/getbc-link <artifact> -o out.bc` instead (same mechanism: reads the
> `.llvm_bc` section, `llvm-link`s the sidecars).

### 1. Build `old.bc` (the baseline)

```bash
git clone https://github.com/libjpeg-turbo/libjpeg-turbo.git
cd libjpeg-turbo
git checkout 3.2.0          # c85e6b90

cmake -G Ninja -DCMAKE_C_COMPILER=gclang \
  -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' \
  -DCMAKE_BUILD_TYPE=Debug -DENABLE_SHARED=1 -DENABLE_STATIC=0 \
  -DENABLE_SIMD=OFF -DWITH_TURBOJPEG=0
ninja

getbc-link libjpeg.so.62.4.0 -o old.bc
```

### 2. Build `pr-syn<N>.bc`

Reset to the baseline, inject one statement into the chosen `src/*.c`'s first
function body, rebuild with the **same** command, save under a new name:

```bash
git reset --hard 3.2.0

# inject (syn3 = src/jchuff.c)
python3 -c "import re; p='src/jchuff.c'; t=open(p).read(); m=re.search(r'\)\s*\{', t); \
  open(p,'w').write(t[:m.end()]+'  volatile int __bench3=sizeof(long)+3; (void)__bench3;\n'+t[m.end():])"

# rebuild with the SAME command as step 1
ninja
getbc-link libjpeg.so.62.4.0 -o pr-syn3.bc
```

`scripts/build_pr_bc.sh libjpeg-turbo` automates this via a `synthetic_touch`
variant (the generic one inserts a comment; this project needs a real statement
because comments are stripped at `-O0` and yield identical bitcode — see the
`build_libjpegturbo` builder).

## Reproduce the results (cb-check analysis)

Three explicit `cb-check` invocations reproduce one data point: **store** the
baseline once, then run a sample **incremental** (reuses stored SEGs) and
**scratch** (no store) to compare.

```bash
CBC=$HOME/github/FermatAnalyzer/build/tools/cb-check/cb-check

# 1) store the baseline once (writes ./persist/libjpeg-turbo/seg/ ...)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -persist-dir=./persist/libjpeg-turbo bc/libjpeg-turbo/old.bc

# 2) incremental on a synthetic (loads clean SEGs, rebuilds only the dirty fn)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -enable-incremental-persist -persist-dir=./persist/libjpeg-turbo bc/libjpeg-turbo/pr-syn3.bc

# 3) scratch on the same bitcode (no store; full rebuild)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only bc/libjpeg-turbo/pr-syn3.bc
```

Run steps 2–3 for each `pr-syn*.bc`. Compare wall-time: incremental wins when it
reuses most SEGs and rebuilds only the dirty function(s).

### Measured (this host, NDEBUG, `-nworkers=8`)

| case | incremental | scratch | SEGs rewritten |
|------|------------:|--------:|---------------:|
| `pr-syn3` (jchuff.c) | ~20 s | ~49 s | 1 |

Incremental rebuilds exactly one function (the touched one) and reuses the other
~927, finishing ~2.5× faster than a full scratch rebuild.

See [`docs/cb-check-incremental-persist.md`](../../docs/cb-check-incremental-persist.md)
and [`../../README.md`](../../README.md#result-columns) for field definitions.
