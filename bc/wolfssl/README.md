# `bc/wolfssl/` — wolfssl bitcode for fermat-check incremental-persist
This folder holds typed-pointer LLVM 15 bitcode for **wolfssl**, used as the input for the `fermat-check` incremental-persist benchmark (`scripts/run_bench.sh`).
## Layout
- **`old.bc`** — the stored baseline. Produced from the upstream source at commit [`5dd7717d1`](https://github.com/wolfSSL/wolfssl/commit/5dd7717d1). `run_bench.sh` stores SEGs from this once; everything else is benchmarked against it.
- **`pr-<NNNN>.bc`** — one bitcode per pull request. Each was produced by applying that PR's source onto the baseline commit and recompiling with the **identical** flags used for `old.bc`. (Names with `pr-syn<N>.bc` are synthetic no-op edits, not real PRs.)
## Build configuration
| | |
|---|---|
| Upstream | `wolfSSL/wolfssl` (<https://github.com/wolfSSL/wolfssl>)
| Baseline commit | `5dd7717d1`
| Artifact extracted | `libwolfssl.so.45.0.0 (shared lib)`
| Toolchain | gllvm `gclang` + `get-bc`, LLVM 15, `-Xclang -no-opaque-pointers`
| Result size | `libwolfssl (~160k inst)`
## Reproduce the .bc files from source
The committed `.bc` files are self-contained, but you can rebuild any of them from the upstream source. The key rule: **`old.bc` and every `pr-*.bc` must use the identical toolchain and flags** so `fermat-check` fingerprints match.
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
git clone https://github.com/wolfSSL/wolfssl.git wolfssl
cd wolfssl
git checkout 5dd7717d1

# build + extract bitcode (artifact: libwolfssl.so.45.0.0 (shared lib))
cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DWOLFSSL_SHARED=ON -DBUILD_SHARED_LIBS=ON -DWOLFSSL_EXAMPLES=OFF -DWOLFSSL_CRYPT_TESTS=OFF
get-bc -o old.bc
```
### 2. Build `pr-NNNN.bc` (one per pull request)
Reset to the baseline, apply the PR's source, rebuild with the **same** command, and save under a new name:
```bash
git reset --hard 5dd7717d1
# fetch the PR ref and copy its changed .c/.h onto the tree
git fetch origin pull/NNNN/head:pr-NNNN
mb=$(git merge-base HEAD pr-NNNN)
git diff --name-only $mb pr-NNNN | grep -E '\.(c|h)$' | \
  while read f; do git show pr-NNNN:$f > $f; done
git branch -D pr-NNNN

# rebuild with the SAME command as step 1
cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DWOLFSSL_SHARED=ON -DBUILD_SHARED_LIBS=ON -DWOLFSSL_EXAMPLES=OFF -DWOLFSSL_CRYPT_TESTS=OFF
get-bc -o pr-NNNN.bc
```
> `scripts/build_pr_bc.sh` automates steps 1-2 for every PR recorded in `results/<proj>/summary.tsv`; run it from the repo root: `./scripts/build_pr_bc.sh wolfssl`.
See [`docs/producing-bitcode.md`](../../docs/producing-bitcode.md) for the full recipe.
## Reproduce the results (fermat-check analysis)
Three explicit `fermat-check` invocations reproduce one data point: **store** the baseline once, then run a sample **incremental** (reuses stored SEGs) and **scratch** (no store) to compare.
```bash
CBC=$HOME/github/FermatAnalyzer/build/tools/fermat-check/fermat-check

# 1) store the baseline once (-serialize-seg → ./persist/wolfssl/<module>/SEG/*.json)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -serialize-seg -store-models-dir=./persist/wolfssl bc/wolfssl/old.bc

# 2) incremental on a PR's bitcode (loads clean SEGs, rebuilds dirty)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -enable-incremental-persist -store-models-dir=./persist/wolfssl bc/wolfssl/pr-NNNN.bc

# 3) scratch on the same bitcode (no store; full rebuild)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only bc/wolfssl/pr-NNNN.bc
```
Run steps 2–3 for each `pr-*.bc` in this folder. Compare the `SEG-Building spends time ***...***` line and the `[Incremental persist] body-dirty: N, +callers: M` line. Incremental wins when `inc` wall-time < `scratch` wall-time.
Result columns and log fields are explained in [`../../docs/fermat-check-incremental-persist.md`](../../docs/fermat-check-incremental-persist.md) and [`../../README.md`](../../README.md#result-columns).
## Files in this folder (13 total)
| File | PR / source | Title | Changed C/C++ files |
|------|-------------|-------|---------------------|
| `old.bc` (4.3M) | baseline `5dd7717d1` | — | — |
| `pr-10936.bc` (4.3M) | [#10936](https://github.com/wolfSSL/wolfssl/pull/10936) | Check ctx extensions before rejecting a TLS1.3 certificate message ext | src/tls.c |
| `pr-10937.bc` (4.3M) | [#10937](https://github.com/wolfSSL/wolfssl/pull/10937) | Fix PKCS7 SignerIdentifier SKID to implicit [0] tagging | tests/api/test_pkcs7.c, tests/api/test_pkcs7.h, wolfcrypt/sr |
| `pr-10938.bc` (4.3M) | [#10938](https://github.com/wolfSSL/wolfssl/pull/10938) | Avoid writing into caller ikm buffer in wc_Tls13_HKDF_Extract | doc/dox_comments/header_files-ja/hmac.h, doc/dox_comments/he |
| `pr-10939.bc` (4.3M) | [#10939](https://github.com/wolfSSL/wolfssl/pull/10939) | Thumb2 ASM: fix out-of-range narrow branches with IAR compiler | wolfcrypt/src/port/arm/thumb2-chacha-asm_c.c, wolfcrypt/src/ |
| `pr-10940.bc` (4.4M) | [#10940](https://github.com/wolfSSL/wolfssl/pull/10940) | ChaCha20/Poly1305 ASM: AVX512 and improvements to other Intel x64 | doc/dox_comments/header_files/chacha20_poly1305.h, src/inter |
| `pr-10941.bc` (4.3M) | [#10941](https://github.com/wolfSSL/wolfssl/pull/10941) | Compliance to new RFCs | doc/dox_comments/header_files/ssl.h, src/internal.c, src/sni |
| `pr-10943.bc` (4.3M) | [#10943](https://github.com/wolfSSL/wolfssl/pull/10943) | Add post-quantum and EdDSA CRL signing | tests/api.c, wolfcrypt/src/asn.c, wolfssl/wolfcrypt/asn_publ |
| `pr-10944.bc` (4.3M) | [#10944](https://github.com/wolfSSL/wolfssl/pull/10944) | Add TLS receive read-ahead support | doc/dox_comments/header_files/ssl.h, examples/benchmark/tls_ |
| `pr-10945.bc` (4.3M) | [#10945](https://github.com/wolfSSL/wolfssl/pull/10945) | OCSP: opt-in fail-closed on missing responder | src/internal.c, src/ocsp.c, src/ssl_certman.c, src/tls.c, te |
| `pr-10946.bc` (4.3M) | [#10946](https://github.com/wolfSSL/wolfssl/pull/10946) | Add hmac-sha3 to benchmark, and macro overrides. | wolfcrypt/benchmark/benchmark.c, wolfcrypt/benchmark/benchma |
| `pr-10947.bc` (4.3M) | [#10947](https://github.com/wolfSSL/wolfssl/pull/10947) | benchmark: build the AArch64 cycle counter under MSVC/ARM64 | wolfcrypt/benchmark/benchmark.c |
| `pr-10948.bc` (4.3M) | [#10948](https://github.com/wolfSSL/wolfssl/pull/10948) | Ed25519 tests: Fix to pass regression testing | tests/api/test_ed25519.c |
