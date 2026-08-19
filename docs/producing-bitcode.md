# Producing LLVM bitcode (`.bc`) for fermat-check

How to compile real C/C++ projects into **typed-pointer** LLVM bitcode that
`fermat-check` can analyze.

Related:

- [fermat-check-modes.md](./fermat-check-modes.md) — store / load / normal analysis
- [fermat-check-incremental-persist.md](./fermat-check-incremental-persist.md) — PR /
  old.bc → new.bc reuse

## Requirements

| Piece | Why |
|-------|-----|
| **LLVM 15 `clang` / `clang++`** | Matches this tree’s fermat-check / LLVM API |
| **Typed pointers** | Pass `-Xclang -no-opaque-pointers`. Opaque-pointer BC is rejected |
| **[gllvm](https://github.com/SRI-CSL/gllvm)** | `gclang` / `gclang++` embed bitcode; `get-bc` extracts a whole-program `.bc` |
| **`-O0 -g`** (recommended) | More IR, less optimization noise; better for analysis / incremental fingerprints |

Install gllvm (Go):

```bash
go install github.com/SRI-CSL/gllvm/cmd/gclang@latest
go install github.com/SRI-CSL/gllvm/cmd/gclang++@latest
go install github.com/SRI-CSL/gllvm/cmd/get-bc@latest
```

Environment (adjust paths to your LLVM 15 install):

```bash
export PATH="$HOME/go/bin:$HOME/tools/llvm15-official/bin:$PATH"
export LLVM_COMPILER_PATH=$HOME/tools/llvm15-official/bin
```

`LLVM_COMPILER_PATH` must point at the directory that contains `clang` used by
gllvm. Verify:

```bash
which gclang get-bc clang
clang --version   # expect 15.x
```

## Golden rule

Use the **same** compiler, flags, and feature toggles for every bitcode you
compare (store vs load, old.bc vs new.bc). Changing `-O`, defines, or optional
deps rewrites IR and invalidates persisted SEGs / fingerprints.

Recommended CFLAGS for analysis:

```text
-O0 -g -fPIC -Xclang -no-opaque-pointers
```

## Workflow (any project)

```text
1. Configure project with CC=gclang (CXX=gclang++)
2. Build the library or binary you care about
3. get-bc -o out.bc <artifact>
4. file out.bc   # should say "LLVM IR bitcode"
5. fermat-check … out.bc
```

`get-bc` works on:

- Shared libraries (`.so`, versioned sonames)
- Executables built with gclang
- Static archives sometimes work, but **prefer a linked `.so` or binary**

If `get-bc` says the file does not exist, resolve the real soname:

```bash
find build -name 'libfoo*.so*' -type f
get-bc -o out.bc build/lib/libfoo-d.so.1.2.3
```

## Project recipes

Paths and sonames may differ slightly by version; adjust after `find` / `ls`.

### curl (cmake, libcurl only)

```bash
cmake -S . -B build-gllvm -G Ninja \
  -DCMAKE_C_COMPILER=gclang \
  -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' \
  -DCMAKE_BUILD_TYPE=Debug \
  -DBUILD_SHARED_LIBS=ON \
  -DCURL_USE_OPENSSL=OFF \
  -DCURL_DISABLE_LDAP=ON \
  -DCURL_USE_LIBPSL=OFF
ninja -C build-gllvm
get-bc -o curl.bc build-gllvm/lib/libcurl-d.so.4.8.0
```

Note: Debug builds often name the library `libcurl-d.so*`. Extracting only
**libcurl** means tool (`src/`) PRs show as IR-clean (`body-dirty: 0`).


### libuv (cmake)

```bash
cmake -S . -B build-gllvm -G Ninja \
  -DCMAKE_C_COMPILER=gclang \
  -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' \
  -DCMAKE_BUILD_TYPE=Debug \
  -DBUILD_TESTING=OFF
ninja -C build-gllvm
get-bc -o libuv.bc build-gllvm/libuv.so.1.0.0
```

### c-ares (cmake)

```bash
cmake -S . -B build-gllvm -G Ninja \
  -DCMAKE_C_COMPILER=gclang \
  -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCARES_SHARED=ON -DCARES_STATIC=OFF
ninja -C build-gllvm
get-bc -o c-ares.bc build-gllvm/lib/libcares.so.2.19.4   # soname may vary
```

### libevent (cmake)

```bash
cmake -S . -B build-gllvm -G Ninja \
  -DCMAKE_C_COMPILER=gclang \
  -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' \
  -DCMAKE_BUILD_TYPE=Debug \
  -DEVENT__LIBRARY_TYPE=SHARED \
  -DEVENT__DISABLE_OPENSSL=ON -DEVENT__DISABLE_MBEDTLS=ON \
  -DEVENT__DISABLE_TESTS=ON -DEVENT__DISABLE_SAMPLES=ON
ninja -C build-gllvm
get-bc -o libevent.bc build-gllvm/lib/libevent_core-2.2.so.1.0.1   # soname may vary
```

### mbedtls (cmake)

```bash
git submodule update --init --recursive    # required
pip install jsonschema jinja2              # mbedtls build scripts need these
cmake -S . -B build-gllvm -G Ninja \
  -DCMAKE_C_COMPILER=gclang \
  -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' \
  -DCMAKE_BUILD_TYPE=Debug \
  -DENABLE_PROGRAMS=OFF -DENABLE_TESTING=OFF \
  -DUSE_SHARED_MBEDTLS_LIBRARY=ON
ninja -C build-gllvm
get-bc -o mbedtls.bc build-gllvm/library/libmbedtls.so.4.2.0   # soname may vary
```

### libyaml (autotools, 0.2.5 tarball)

```bash
./configure CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' \
  --disable-shared --enable-static --disable-dependency-tracking
make -j$(nproc)
llvm-link -o libyaml.bc src/.api.o.bc src/.dumper.o.bc src/.emitter.o.bc \
  src/.loader.o.bc src/.parser.o.bc src/.reader.o.bc src/.scanner.o.bc \
  src/.writer.o.bc
```

### libexpat (autotools, 2.6.3 tarball)

```bash
./configure CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' \
  --disable-shared --enable-static --without-docbook --without-xmlwf \
  --disable-dependency-tracking
make -j$(nproc)
llvm-link -o libexpat.bc lib/.xmlparse.o.bc lib/.xmltok.o.bc lib/.xmlrole.o.bc
```

### libsodium (autotools, 1.0.20-stable tarball)

```bash
# get-bc on libsodium.a may fail; llvm-link gllvm per-TU .bc instead
./configure CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' \
  --disable-shared --enable-static --disable-dependency-tracking
make -j$(nproc)
find src/libsodium -name '*.bc' | sort | xargs llvm-link -o libsodium.bc
```

### openssh-portable (autotools)

```bash
autoreconf -fi
./configure CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers'
make -j$(nproc) sshd        # build just the server
get-bc -o openssh.bc sshd
```

### memcached (autotools; needs libevent)

```bash
# 1. install libevent first (see libevent recipe above), e.g.:
#    cmake --install <libevent build dir> --prefix /tmp/libevent-install
# 2. build memcached
./autogen.sh
autoreconf -fi && automake --add-missing --copy
./configure CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' \
  --with-libevent=/tmp/libevent-install \
  LDFLAGS='-L/tmp/libevent-install/lib -Wl,-rpath,/tmp/libevent-install/lib' \
  CPPFLAGS='-I/tmp/libevent-install/include'
make -j$(nproc)
get-bc -o memcached.bc memcached
```

### darknet (Makefile)

```bash
make -j$(nproc) CC=gclang CPP=gclang++ DEBUG=1 GPU=0 \
  CFLAGS='-Wall -Wno-unused-result -Wno-unknown-pragmas -Wfatal-errors -fPIC -O0 -g -Xclang -no-opaque-pointers'
get-bc -o darknet.bc darknet
```



### CMake projects (generic)

```bash
cmake -S . -B build-gllvm -G Ninja \
  -DCMAKE_C_COMPILER=gclang \
  -DCMAKE_CXX_COMPILER=gclang++ \
  -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' \
  -DCMAKE_CXX_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' \
  -DCMAKE_BUILD_TYPE=Debug
ninja -C build-gllvm
get-bc -o out.bc path/to/lib_or_binary
```

### Autotools projects (generic)

```bash
./configure CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers'
make -j$(nproc)
get-bc -o out.bc path/to/lib_or_binary
```

## Sanity checks

```bash
file out.bc
# expect: LLVM IR bitcode

llvm-dis -o - out.bc 2>/dev/null | head -5
# expect: ; ModuleID = ...  (and typed pointers like i8*, not ptr)

# smoke fermat-check
fermat-check --hide-progress-bar -nworkers=4 -enable-build-seg-only out.bc
```

If fermat-check errors about opaque pointers, rebuild with
`-Xclang -no-opaque-pointers` and re-run `get-bc`.

## Common failures

| Symptom | Fix |
|---------|-----|
| `get-bc`: input file does not exist | Use real file, not a broken symlink; check Debug soname (`libfoo-d.so`) |
| `get-bc`: no bitcode embedded | Artifact was not built with `gclang` / `gclang++` |
| clang not found by gllvm | Set `LLVM_COMPILER_PATH` to LLVM 15 `bin` |
| Opaque pointer / type errors in fermat-check | Add `-Xclang -no-opaque-pointers` and rebuild |
| Huge missing-dep / feature errors | Disable optional deps (OpenSSL, LDAP, GPU, tests) for a lean analysis build |
| PR rebuild fails after copying a few files | Headers/API drift; need more files or a clean merge, not partial copies |

## PR / incremental: keep old.bc and new.bc comparable

1. Build `old.bc` on a fixed baseline commit.
2. Apply PR changes (or merge), rebuild with **identical** gllvm flags.
3. `get-bc -o new.bc …` from the **same kind** of artifact (same `.so` or
   binary).

See [fermat-check-incremental-persist.md](./fermat-check-incremental-persist.md) for
store / incremental flags and measured project sizes.

## Size ballpark (from local benches)

| Project | Artifact | Approx size | Functions / inst (order of) |
|---------|----------|------------:|-----------------------------|
| memcached | `memcached` | ~2 MB | ~0.6k fn / ~15k inst |
| openssh | `sshd` | ~3 MB | ~1.8k fn / ~75k inst |
| c-ares | `libcares.so` | ~2 MB | ~1k fn / ~40k inst |
| mbedtls | `libmbedtls.so` | ~2 MB | ~0.8k fn / ~25k inst |
| libsodium | `libsodium` (linked TUs) | ~2.5 MB | ~1.1k fn |
| libexpat | `xmlparse+xmltok+xmlrole` | ~0.9 MB | ~0.4k fn |
| libyaml | `libyaml` TUs | ~0.7 MB | ~0.2k fn |
| libevent | `libevent_core.so` | ~1 MB | ~0.7k fn / ~30k inst |
| libuv | `libuv.so` | few MB | ~1k fn / ~50k inst |
| curl | `libcurl` | ~7 MB | ~2.5k fn / ~220k inst |
| darknet | `darknet` | tens of MB | ~1k fn / ~120k inst |

## See also

- [fermat-check-modes.md](./fermat-check-modes.md)
- [fermat-check-incremental-persist.md](./fermat-check-incremental-persist.md)
- [gllvm](https://github.com/SRI-CSL/gllvm)
