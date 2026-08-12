# `bc/libyaml/` — libyaml bitcode for fermat-check incremental-persist

Typed-pointer LLVM 15 bitcode for **libyaml**. Medium-tier runtime: full
`--ps-npd` ~1.5–2 min on 16 workers (~194 functions, ~720 KB `.bc`).

## Layout

- **`old.bc`** — baseline from **yaml 0.2.5** (api/dumper/emitter/loader/parser/reader/scanner/writer).
- **`pr-syn0.bc` / `pr-syn1.bc`** — synthetic comments in `parser.c` / `scanner.c`.

## Build configuration

| | |
|---|---|
| Upstream | [yaml/libyaml](https://github.com/yaml/libyaml) |
| Baseline | 0.2.5 release tarball |
| Artifact | `src/.*.o.bc` → `llvm-link` |
| Toolchain | gllvm `gclang` + LLVM 15, `-O0 -g -fPIC -Xclang -no-opaque-pointers` |
| Size | ~720 KB bitcode / ~194 functions |

## Reproduce `old.bc`

```bash
export LLVM_COMPILER_PATH=$HOME/tools/llvm15-official/bin
export PATH=$HOME/go/bin:$LLVM_COMPILER_PATH:$PATH
export LLVM_COMPILER=clang

curl -sL https://github.com/yaml/libyaml/releases/download/0.2.5/yaml-0.2.5.tar.gz \
  | tar xz
cd yaml-0.2.5
./configure CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' \
  --disable-shared --enable-static --disable-dependency-tracking
make -j$(nproc)
llvm-link -o old.bc src/.api.o.bc src/.dumper.o.bc src/.emitter.o.bc \
  src/.loader.o.bc src/.parser.o.bc src/.reader.o.bc src/.scanner.o.bc \
  src/.writer.o.bc
```
