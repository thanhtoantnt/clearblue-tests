# `bc/unbound/` — unbound bitcode for fermat-check incremental-persist

Typed-pointer LLVM 15 bitcode for **unbound** (NLnetLabs DNS resolver).
Sized next to OpenSSH: ~3.5k functions / ~327k inst; 7-checker PSA
(`-ps-npd -ps-uaf -ps-ml -ps-iusa -ps-uuv -ps-fdl -ps-fnhm`, nworkers=32)
~15–18 min.

## Layout

- **`old.bc`** — baseline from tag `release-1.25.2` (`c33ad1b1a`).
  Artifact: the `unbound` daemon binary.

## Build configuration

| | |
|---|---|
| Upstream | [NLnetLabs/unbound](https://github.com/NLnetLabs/unbound) |
| Baseline | `release-1.25.2` / `c33ad1b1a` |
| Artifact | `unbound` (daemon) |
| Toolchain | gllvm `gclang` + LLVM 15, `-O0 -g -fPIC -Xclang -no-opaque-pointers` |
| Size | ~8.3 MB bitcode / ~3469 functions / ~327k inst |

## Reproduce `old.bc`

```bash
export LLVM_COMPILER_PATH=$HOME/tools/llvm15-official/bin
export PATH=$HOME/go/bin:$LLVM_COMPILER_PATH:$PATH

git clone https://github.com/NLnetLabs/unbound.git unbound
cd unbound && git checkout c33ad1b1a
./configure CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' \
  --disable-shared --enable-static \
  --without-pyunbound --without-pythonmodule \
  --disable-flto --disable-rpath \
  --with-libevent=no --with-libhiredis=no
make -j$(nproc) unbound
getbc-link unbound -o old.bc     # get-bc is broken on some hosts
```

Or from this repo: `./scripts/build_old_bc.sh unbound`.
