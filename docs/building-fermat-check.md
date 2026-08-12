# Building `fermat-check`

`fermat-check` is the static analyzer (part of the [FermatAnalyzer](https://github.com/fermat-hkrc/FermatAnalyzer) / "Clearblue" project) that consumes the `.bc` files in this repo and runs the store / incremental / scratch analyses. This page records **exactly how the binary used to produce the numbers in this repo was built**, so the results are reproducible.

The same procedure builds the stock analyzer; the incremental-persist feature used here lives on the `feature/incremental-persist-reuse` branch.

## TL;DR

```bash
# 1. you need a custom LLVM 15 built WITH RTTI + exceptions (the stock
#    LLVM release disables both, but FermatAnalyzer links against it and
#    needs them)
# 2. configure + build FermatAnalyzer against that LLVM (flags straight
#    from the upstream README)
cmake -S . -B build -G Ninja \
  -DCMAKE_C_COMPILER=$HOME/tools/llvm15-rtti/bin/clang \
  -DCMAKE_CXX_COMPILER=$HOME/tools/llvm15-rtti/bin/clang++ \
  -DLLVM_BUILD_PATH=$HOME/tools/llvm15-rtti \
  -DLLVM_ENABLE_RTTI=ON -DLLVM_ENABLE_EH=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_LICENCE_CHECK=OFF -DENABLE_LOADABLE_CHECKERS=OFF \
  -DFERMAT_STATIC_EXE=ON -DENABLE_STATICZ3=ON -DENABLE_ASSERT=ON \
  -DCMAKE_INSTALL_PREFIX=$PWD/build/fermat
cmake --build build --target fermat-check -j$(nproc)
# -> build/tools/fermat-check/fermat-check
```

---

## Why a custom LLVM? (the RTTI gotcha)

LLVM's **official releases are built with RTTI and exceptions disabled**
(`LLVM_ENABLE_RTTI=OFF`, `LLVM_ENABLE_EH=OFF`). FermatAnalyzer's code is
written against an LLVM that has them **on**, so linking against the stock
release produces a flood of `-fno-rtti` / undefined-`typeinfo` errors at link
time.

The fix is to build LLVM 15 once with those two flags flipped on. We keep two
parallel installs side by side:

| Install | RTTI / EH | Used by |
|---------|-----------|---------|
| `~/tools/llvm15-official` | OFF / OFF | **gllvm** — `gclang` used to compile the `.bc` inputs (stock LLVM is fine for bitcode generation) |
| `~/tools/llvm15-rtti`     | **ON / ON** | **fermat-check** — the analyzer itself must link against RTTI-enabled LLVM |

Both are LLVM 15.x (15.0.6 official / 15.0.7 rtti). Mixing is safe: the
`.bc` format is identical; only the host toolchain ABI differs.

### Building the RTTI-enabled LLVM 15

```bash
# fetch llvm + clang 15.0.7 sources (llvm-project release/15.x)
git clone --branch release/15.x --depth 1 \
  https://github.com/llvm/llvm-project.git
cd llvm-project

cmake -S llvm -B build-rtti -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS="clang" \
  -DLLVM_ENABLE_RTTI=ON \
  -DLLVM_ENABLE_EH=ON \
  -DCMAKE_INSTALL_PREFIX=$HOME/tools/llvm15-rtti
cmake --build build-rtti -j$(nproc)
cmake --install build-rtti

# sanity check
$HOME/tools/llvm15-rtti/bin/clang++ --version   # clang version 15.0.7
grep -E 'LLVM_ENABLE_RTTI|LLVM_ENABLE_EH' \
  $HOME/tools/llvm15-rtti/lib/cmake/llvm/LLVMConfig.cmake
#   -> set(LLVM_ENABLE_RTTI ON)   /   set(LLVM_ENABLE_EH ON)
```

This is a one-time, ~20–40 min build. `clang` is included so the same
toolchain can compile the analyzer sources.

---

## Building FermatAnalyzer / `fermat-check`

### Prerequisites

- **CMake ≥ 3.13** (3.28 used here; binary at `~/tools/cmake-3.28.2/bin/cmake`)
- **Ninja** (the build uses `build.ninja`)
- The RTTI-enabled LLVM 15 from the step above
- A C/C++ compiler for the bootstrap (the rtti LLVM's own `clang` is fine)

### Configure + build

```bash
git clone https://github.com/fermat-hkrc/FermatAnalyzer.git
cd FermatAnalyzer

# the incremental-persist feature is on this branch
git checkout feature/incremental-persist-reuse

LLVM=$HOME/tools/llvm15-rtti

cmake -S . -B build -G Ninja \
    -DCMAKE_C_COMPILER=$LLVM/bin/clang \
    -DCMAKE_CXX_COMPILER=$LLVM/bin/clang++ \
    -DLLVM_BUILD_PATH=$LLVM \
    -DLLVM_ENABLE_RTTI=ON -DLLVM_ENABLE_EH=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_LICENCE_CHECK=OFF \
    -DENABLE_LOADABLE_CHECKERS=OFF \
    -DFERMAT_STATIC_EXE=ON \
    -DENABLE_STATICZ3=ON \
    -DENABLE_ASSERT=ON \
    -DCMAKE_INSTALL_PREFIX="$PWD/build/fermat"

cmake --build build --target fermat-check -j$(nproc)

# result (~67 MB statically linked binary)
ls -la build/tools/fermat-check/fermat-check
# (the README runs `ninja install`, which also stages it under
#  build/fermat/bin/fermat-check; here only `--target fermat-check` was built,
#  so use the build/tools/fermat-check/fermat-check path directly)
```

`FERMAT_STATIC_EXE=ON` produces a self-contained binary (no `LD_LIBRARY_PATH`
needed for the analyzer's own libs). The binary embeds the project name, the
git commit it was built from, and a build timestamp via `CMakeLists.txt`.

> **Variable-name note:** the README uses `-DLLVM_BUILD_PATH=` and
> `-DFERMAT_STATIC_EXE=`. Internally CMake derives `LLVM_DIR` from
> `LLVM_BUILD_PATH` and sets `CLEARBLUE_STATIC_EXE` from `FERMAT_STATIC_EXE`
> — so the cmake *cache* shows both spellings. Use the README names.
> The flags `ENABLE_STATICZ3=ON` (bundle z3), `ENABLE_LICENCE_CHECK=OFF`,
> `ENABLE_LOADABLE_CHECKERS=OFF`, and `ENABLE_ASSERT=ON` are exactly as
> the upstream README specifies them.

### Verify it works

```bash
CBC=$PWD/build/tools/fermat-check/fermat-check
$CBC --help 2>&1 | head
# smoke test against a committed baseline
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     ~/clearblue/incremental-persist-bench/bc/c-ares/old.bc
```

---

## The binary used for the numbers in this repo

| | |
|---|---|
| Source | `FermatAnalyzer` @ `feature/incremental-persist-reuse`, commit `8d121812` |
| Built | `2025-07-14` (binary mtime) |
| Build type | `Release` |
| Host toolchain | `clang/clang++ 15.0.7` (RTTI+EH build) |
| LLVM linked | `llvm15-rtti` (15.0.7, `LLVM_ENABLE_RTTI=ON`, `LLVM_ENABLE_EH=ON`) |
| Binary | `build/tools/fermat-check/fermat-check`, ~67 MB |
| Path referenced in docs | `$HOME/github/FermatAnalyzer/build/tools/fermat-check/fermat-check` |

To reproduce the benchmark numbers **exactly**, build the same commit with the
same flags. Different commits may give slightly different times (analysis logic
changes), but the *incremental-vs-scratch speedup ratio* is stable across
builds.
