# `bc/libsodium/` — libsodium bitcode for fermat-check incremental-persist

Typed-pointer LLVM 15 bitcode for **libsodium**, sized like other medium
projects in this suite (~2.5 MB `.bc`, ~1.1k functions, full `--ps-npd` ~35 s
on a 16-worker machine).

## Layout

- **`old.bc`** — baseline from upstream **libsodium 1.0.20-stable**
  (`SODIUM_VERSION_STRING "1.0.20"`).
- **`pr-syn0.bc` / `pr-syn1.bc`** — synthetic no-op edits (comment lines in
  `sodium/utils.c` and `sodium/core.c`), not real GitHub PRs. Enough to
  exercise incremental dirty-set + store/load.

## Build configuration

| | |
|---|---|
| Upstream | [jedisct1/libsodium](https://github.com/jedisct1/libsodium) |
| Baseline | 1.0.20-stable release tarball |
| Artifact | all `src/libsodium/**/*.bc` from gllvm, `llvm-link`’d |
| Toolchain | gllvm `gclang` + LLVM 15, `-O0 -g -fPIC -Xclang -no-opaque-pointers` |
| Size | ~2.5 MB bitcode / ~1119 functions |

## Reproduce `old.bc`

```bash
export LLVM_COMPILER_PATH=$HOME/tools/llvm15-official/bin
export PATH=$HOME/go/bin:$LLVM_COMPILER_PATH:$PATH
export LLVM_COMPILER=clang

curl -sL https://download.libsodium.org/libsodium/releases/libsodium-1.0.20-stable.tar.gz \
  | tar xz
cd libsodium-stable
./configure CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' \
  --disable-shared --enable-static --disable-dependency-tracking
make -j$(nproc)

# gllvm leaves per-TU .bc next to objects; link (get-bc may fail on .a here)
find src/libsodium -name '*.bc' | sort > /tmp/bcs.txt
xargs llvm-link -o old.bc < /tmp/bcs.txt
```

## Synthetic PR bitcode

```bash
# example: pr-syn0
echo '/* bench-syn0 */' >> src/libsodium/sodium/utils.c
make -j$(nproc)
find src/libsodium -name '*.bc' | sort | xargs llvm-link -o pr-syn0.bc
```
