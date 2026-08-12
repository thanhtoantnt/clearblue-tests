# `bc/libexpat/` — Expat bitcode for fermat-check incremental-persist

Typed-pointer LLVM 15 bitcode for **libexpat** (XML parser). Medium-tier
runtime: full `--ps-npd` ~3–4 min on 16 workers (~359 functions, ~860 KB `.bc`).

## Layout

- **`old.bc`** — baseline from **expat 2.6.3** (`xmlparse` + `xmltok` + `xmlrole`).
- **`pr-syn0.bc` / `pr-syn1.bc`** — synthetic comment edits in `xmlparse.c` /
  `xmltok.c` (not real GitHub PRs).

## Build configuration

| | |
|---|---|
| Upstream | [libexpat/libexpat](https://github.com/libexpat/libexpat) |
| Baseline | 2.6.3 release tarball |
| Artifact | `lib/.xml{parse,tok,role}.o.bc` → `llvm-link` |
| Toolchain | gllvm `gclang` + LLVM 15, `-O0 -g -fPIC -Xclang -no-opaque-pointers` |
| Size | ~860 KB bitcode / ~359 functions |

## Reproduce `old.bc`

```bash
export LLVM_COMPILER_PATH=$HOME/tools/llvm15-official/bin
export PATH=$HOME/go/bin:$LLVM_COMPILER_PATH:$PATH
export LLVM_COMPILER=clang

curl -sL https://github.com/libexpat/libexpat/releases/download/R_2_6_3/expat-2.6.3.tar.gz \
  | tar xz
cd expat-2.6.3
./configure CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' \
  --disable-shared --enable-static --without-docbook --without-xmlwf \
  --disable-dependency-tracking
make -j$(nproc)
llvm-link -o old.bc lib/.xmlparse.o.bc lib/.xmltok.o.bc lib/.xmlrole.o.bc
```
