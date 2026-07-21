# `bc/openssl/` — openssl bitcode for cb-check incremental-persist
This folder holds typed-pointer LLVM 15 bitcode for **openssl**, used as the input for the `cb-check` incremental-persist benchmark (`scripts/run_bench.sh`).
## Layout
- **`old.bc`** — the stored baseline. Produced from the upstream source at commit [`380d6afcb3`](https://github.com/openssl/openssl/commit/380d6afcb3). `run_bench.sh` stores SEGs from this once; everything else is benchmarked against it.
- **`pr-<NNNN>.bc`** — one bitcode per pull request. Each was produced by applying that PR's source onto the baseline commit and recompiling with the **identical** flags used for `old.bc`. (Names with `pr-syn<N>.bc` are synthetic no-op edits, not real PRs.)
## Build configuration
| | |
|---|---|
| Upstream | `openssl/openssl` (<https://github.com/openssl/openssl>)
| Baseline commit | `380d6afcb3`
| Artifact extracted | `libcrypto.so.3 (libcrypto only)`
| Toolchain | gllvm `gclang` + `get-bc`, LLVM 15, `-Xclang -no-opaque-pointers`
| Result size | `libcrypto (~900k inst)`
## Reproduce the .bc files from source
The committed `.bc` files are self-contained, but you can rebuild any of them from the upstream source. The key rule: **`old.bc` and every `pr-*.bc` must use the identical toolchain and flags** so `cb-check` fingerprints match.
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
git clone https://github.com/openssl/openssl.git openssl
cd openssl
git checkout 380d6afcb3

# build + extract bitcode (artifact: libcrypto.so.3 (libcrypto only))
./config CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' no-asm shared -d ; make build_libs
get-bc -o old.bc
```
### 2. Build `pr-NNNN.bc` (one per pull request)
Reset to the baseline, apply the PR's source, rebuild with the **same** command, and save under a new name:
```bash
git reset --hard 380d6afcb3
# fetch the PR ref and copy its changed .c/.h onto the tree
git fetch origin pull/NNNN/head:pr-NNNN
mb=$(git merge-base HEAD pr-NNNN)
git diff --name-only $mb pr-NNNN | grep -E '\.(c|h)$' | \
  while read f; do git show pr-NNNN:$f > $f; done
git branch -D pr-NNNN

# rebuild with the SAME command as step 1
./config CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' no-asm shared -d ; make build_libs
get-bc -o pr-NNNN.bc
```
> `scripts/build_pr_bc.sh` automates steps 1-2 for every PR recorded in `results/<proj>/summary.tsv`; run it from the repo root: `./scripts/build_pr_bc.sh openssl`.
See [`docs/producing-bitcode.md`](../../docs/producing-bitcode.md) for the full recipe.
## Reproduce the results (cb-check analysis)
Three explicit `cb-check` invocations reproduce one data point: **store** the baseline once, then run a sample **incremental** (reuses stored SEGs) and **scratch** (no store) to compare.
```bash
CBC=$HOME/github/FermatAnalyzer/build/tools/cb-check/cb-check

# 1) store the baseline once (writes ./persist/openssl/seg/ ...)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -persist-dir=./persist/openssl bc/openssl/old.bc

# 2) incremental on a PR's bitcode (loads clean SEGs, rebuilds dirty)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -enable-incremental-persist -persist-dir=./persist/openssl bc/openssl/pr-NNNN.bc

# 3) scratch on the same bitcode (no store; full rebuild)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only bc/openssl/pr-NNNN.bc
```
Run steps 2–3 for each `pr-*.bc` in this folder. Compare the `SEG-Building spends time ***...***` line and the `[Incremental persist] body-dirty: N, +callers: M` line. Incremental wins when `inc` wall-time < `scratch` wall-time.
Result columns and log fields are explained in [`../../docs/cb-check-incremental-persist.md`](../../docs/cb-check-incremental-persist.md) and [`../../README.md`](../../README.md#result-columns).
## Files in this folder (20 total)
| File | PR / source | Title | Changed C/C++ files |
|------|-------------|-------|---------------------|
| `old.bc` (25M) | baseline `380d6afcb3` | — | — |
| `pr-31906.bc` (25M) | [#31906](https://github.com/openssl/openssl/pull/31906) | [test] check late AAD rejection across AEADs | providers/implementations/ciphers/cipher_chacha20_poly1305_h |
| `pr-31909.bc` (25M) | [#31909](https://github.com/openssl/openssl/pull/31909) | x509 store: keep store object lists sorted for O(log n) duplicate dete | crypto/x509/by_dir.c, crypto/x509/by_store.c, crypto/x509/x5 |
| `pr-31913.bc` (25M) | [#31913](https://github.com/openssl/openssl/pull/31913) | Drop Windows-on-Itanium (VC-WIN64I) support. | ms/uplink.c |
| `pr-31915.bc` (25M) | [#31915](https://github.com/openssl/openssl/pull/31915) | test: add Windows unit tests setup and initial dgram test | test/unit/crypto/bio/test_bss_dgram_win.c |
| `pr-31916.bc` (25M) | [#31916](https://github.com/openssl/openssl/pull/31916) | Avoid undefined behavior adding two BN_zero() values | crypto/bn/bn_add.c |
| `pr-31918.bc` (25M) | [#31918](https://github.com/openssl/openssl/pull/31918) | quic-radix: add thread-assisted idle keepalive test | test/radix/quic_bindings.c, test/radix/quic_ops.c, test/radi |
| `pr-31924.bc` (25M) | [#31924](https://github.com/openssl/openssl/pull/31924) | quic: make tserver fake-time idle test deterministic | test/quic_tserver_test.c |
| `pr-31925.bc` (25M) | [#31925](https://github.com/openssl/openssl/pull/31925) | Fix known PSK/ticket issues (master) | ssl/record/rec_layer_s3.c, ssl/ssl_ciph.c, ssl/ssl_lib.c, ss |
| `pr-31928.bc` (25M) | [#31928](https://github.com/openssl/openssl/pull/31928) | TLS 1.3: Fix SSL_export_keying_material_early() when 0-RTT is suppress | ssl/ssl_lib.c, ssl/ssl_local.h, ssl/ssl_sess.c, ssl/statem/e |
| `pr-31929.bc` (25M) | [#31929](https://github.com/openssl/openssl/pull/31929) | Optimize ML-KEM for the s390x architecture | crypto/ml_kem/ml_kem.c, crypto/ml_kem/ml_kem_local.h, crypto |
| `pr-31931.bc` (25M) | [#31931](https://github.com/openssl/openssl/pull/31931) | The wrong comment about the BN_FLG_STATIC_DATA flag. | crypto/bn/bn_lib.c |
| `pr-31933.bc` (25M) | [#31933](https://github.com/openssl/openssl/pull/31933) | OSSL_FN: Add modular multiplicative inverse [pending #30822, #31830, # | crypto/fn/fn_addsub.c, crypto/fn/fn_div.c, crypto/fn/fn_err. |
| `pr-31938.bc` (25M) | [#31938](https://github.com/openssl/openssl/pull/31938) | rand: pre-fetch JITTER seed when jitter used | test/rand_test.c |
| `pr-31939.bc` (25M) | [#31939](https://github.com/openssl/openssl/pull/31939) | rand: honour explicitly configured seed source in provider callbacks | crypto/rand/prov_seed.c, crypto/rand/rand_lib.c, include/cry |
| `pr-31940.bc` (25M) | [#31940](https://github.com/openssl/openssl/pull/31940) | [providers/implementations/ciphers] GCM-SIV: reject out-of-order updat | providers/implementations/ciphers/cipher_aes_gcm_siv_hw.c, t |
| `pr-31943.bc` (25M) | [#31943](https://github.com/openssl/openssl/pull/31943) | [Coverity] Check the return values of BN_hex2bn in tests | test/bntest.c, test/ectest.c, test/srptest.c |
| `pr-31945.bc` (25M) | [#31945](https://github.com/openssl/openssl/pull/31945) | Remove QUIC_TSERVER: Move script_13 to script_14 | test/quic_multistream_test.c, test/radix/quic_tests.c |
| `pr-31954.bc` (25M) | [#31954](https://github.com/openssl/openssl/pull/31954) | Fix dsaparams decoding from DER files | apps/lib/apps.c |
| `pr-31957.bc` (25M) | [#31957](https://github.com/openssl/openssl/pull/31957) | Add some missing value_barrier calls | crypto/bn/bn_exp.c, crypto/bn/bn_lib.c |
