# `bc/curl/` — curl bitcode for cb-check incremental-persist
This folder holds typed-pointer LLVM 15 bitcode for **curl**, used as the input for the `cb-check` incremental-persist benchmark (`scripts/run_bench.sh`).
## Layout
- **`old.bc`** — the stored baseline. Produced from the upstream source at commit [`bc440a89d4`](https://github.com/curl/curl/commit/bc440a89d4). `run_bench.sh` stores SEGs from this once; everything else is benchmarked against it.
- **`pr-<NNNN>.bc`** — one bitcode per pull request. Each was produced by applying that PR's source onto the baseline commit and recompiling with the **identical** flags used for `old.bc`. (Names with `pr-syn<N>.bc` are synthetic no-op edits, not real PRs.)
## Build configuration
| | |
|---|---|
| Upstream | `curl/curl` (<https://github.com/curl/curl>)
| Baseline commit | `bc440a89d4`
| Artifact extracted | `libcurl-d.so.4.8.0 (libcurl, shared, no OpenSSL/LDAP/libpsl)`
| Toolchain | gllvm `gclang` + `get-bc`, LLVM 15, `-Xclang -no-opaque-pointers`
| Result size | `libcurl (debug shared lib)`
```bash
# how each .bc was built (same for old.bc and every pr-*.bc)
cmake -G Ninja -DCMAKE_C_COMPILER=gclang -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' -DCMAKE_BUILD_TYPE=Debug -DBUILD_SHARED_LIBS=ON -DCURL_USE_OPENSSL=OFF -DCURL_DISABLE_LDAP=ON -DCURL_USE_LIBPSL=OFF
get-bc -o <file>.bc <artifact>
```
See [`docs/producing-bitcode.md`](../../docs/producing-bitcode.md) for the full recipe.
## Files in this folder (11 total)
| File | PR / source | Title | Changed C/C++ files |
|------|-------------|-------|---------------------|
| `old.bc` (6.6M) | baseline `bc440a89d4` | — | — |
| `pr-22304.bc` (6.6M) | [#22304](https://github.com/curl/curl/pull/22304) | fix event-based connection shutdown and add a test for it | lib/cfilters.c, lib/connect.c, lib/connect.h, lib/cshutdn.c, |
| `pr-22309.bc` (6.6M) | [#22309](https://github.com/curl/curl/pull/22309) | setopt: reject CR and LF octets in curl_slists given to options | lib/setopt.c, src/config2setopts.c, tests/libtest/lib2017.c |
| `pr-22310.bc` (6.6M) | [#22310](https://github.com/curl/curl/pull/22310) | rtsp: reject control bytes in stream URI, transport and session ID | lib/rtsp.c, tests/libtest/lib657.c |
| `pr-22313.bc` (6.6M) | [#22313](https://github.com/curl/curl/pull/22313) | urlapi: allow URLs to have no userauth (hostname) | lib/urlapi.c, tests/libtest/lib1560.c |
| `pr-22315.bc` (6.6M) | [#22315](https://github.com/curl/curl/pull/22315) | tool_getparam: reject argument to options using CRLF | src/tool_getparam.c, src/tool_getparam.h |
| `pr-22317.bc` (6.6M) | [#22317](https://github.com/curl/curl/pull/22317) | ngtcp2: let verify failures win over expiry processing errors | lib/vquic/cf-ngtcp2-cmn.c |
| `pr-22322.bc` (6.6M) | [#22322](https://github.com/curl/curl/pull/22322) | mime.c: avoid integer overflow in base64 size calculation | lib/mime.c |
| `pr-22324.bc` (6.6M) | [#22324](https://github.com/curl/curl/pull/22324) | ssls: fix import leak | lib/vtls/vtls_scache.c, lib/vtls/vtls_scache.h, lib/vtls/vtl |
| `pr-22326.bc` (6.6M) | [#22326](https://github.com/curl/curl/pull/22326) | idn: restore `MultiByteToWideChar()` `MB_ERR_INVALID_CHARS` flag | lib/curlx/fopen.c, lib/curlx/multibyte.c, lib/idn.c, lib/vtl |
| `pr-22328.bc` (6.6M) | [#22328](https://github.com/curl/curl/pull/22328) | tool_cb_prg: avoid integer overflows | src/tool_cb_prg.c |
