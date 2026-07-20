# `bc/openssh/` — openssh bitcode for cb-check incremental-persist
This folder holds typed-pointer LLVM 15 bitcode for **openssh**, used as the input for the `cb-check` incremental-persist benchmark (`scripts/run_bench.sh`).
## Layout
- **`old.bc`** — the stored baseline. Produced from the upstream source at commit [`cadefc724`](https://github.com/openssh/openssh-portable/commit/cadefc724). `run_bench.sh` stores SEGs from this once; everything else is benchmarked against it.
- **`pr-<NNNN>.bc`** — one bitcode per pull request. Each was produced by applying that PR's source onto the baseline commit and recompiling with the **identical** flags used for `old.bc`. (Names with `pr-syn<N>.bc` are synthetic no-op edits, not real PRs.)
## Build configuration
| | |
|---|---|
| Upstream | `openssh/openssh-portable` (<https://github.com/openssh/openssh-portable>)
| Baseline commit | `cadefc724`
| Artifact extracted | `sshd (server binary)`
| Toolchain | gllvm `gclang` + `get-bc`, LLVM 15, `-Xclang -no-opaque-pointers`
| Result size | `sshd (~75k inst)`
```bash
# how each .bc was built (same for old.bc and every pr-*.bc)
autoreconf -fi ; ./configure CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' ; make sshd
get-bc -o <file>.bc <artifact>
```
See [`docs/producing-bitcode.md`](../../docs/producing-bitcode.md) for the full recipe.
## Reproduce the results
Three explicit `cb-check` invocations reproduce one data point: **store** the baseline once, then run a sample **incremental** (reuses stored SEGs) and **scratch** (no store) to compare.
```bash
CBC=$HOME/github/FermatAnalyzer/build/tools/cb-check/cb-check

# 1) store the baseline once (writes ./persist/openssh/seg/ ...)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -persist-dir=./persist/openssh bc/openssh/old.bc

# 2) incremental on a PR's bitcode (loads clean SEGs, rebuilds dirty)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -enable-incremental-persist -persist-dir=./persist/openssh bc/openssh/pr-NNNN.bc

# 3) scratch on the same bitcode (no store; full rebuild)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only bc/openssh/pr-NNNN.bc
```
Run steps 2–3 for each `pr-*.bc` in this folder. Compare the `SEG-Building spends time ***...***` line and the `[Incremental persist] body-dirty: N, +callers: M` line. Incremental wins when `inc` wall-time < `scratch` wall-time.
Result columns and log fields are explained in [`../../docs/cb-check-incremental-persist.md`](../../docs/cb-check-incremental-persist.md) and [`../../README.md`](../../README.md#result-columns).
## Files in this folder (12 total)
| File | PR / source | Title | Changed C/C++ files |
|------|-------------|-------|---------------------|
| `old.bc` (3.0M) | baseline `cadefc724` | — | — |
| `pr-688.bc` (3.0M) | [#688](https://github.com/openssh/openssh-portable/pull/688) | Fix path truncation vulnerability in sftp-server readdir | sftp-server.c, test_sftp_readdir_overflow.c |
| `pr-689.bc` (3.0M) | [#689](https://github.com/openssh/openssh-portable/pull/689) | validate restored cipher key and IV lengths | packet.c |
| `pr-690.bc` (3.0M) | [#690](https://github.com/openssh/openssh-portable/pull/690) | Update monitor.c mm_answer_gss_userok: enforce prior GSSCHECKMIC | monitor.c |
| `pr-691.bc` (3.0M) | [#691](https://github.com/openssh/openssh-portable/pull/691) | Fuzz/sk fido2 oom | regress/misc/fuzz-harness/sk_sign_wiredata.h, sk-usbhid.c |
| `pr-693.bc` (3.0M) | [#693](https://github.com/openssh/openssh-portable/pull/693) | sftp: set CLOEXEC on ssh subprocess IPC descriptors | sftp.c |
| `pr-694.bc` (3.0M) | [#694](https://github.com/openssh/openssh-portable/pull/694) | add missing entries for MLDSA44ED25519 hybrid for sshfp | dns.c, dns.h |
| `pr-695.bc` (3.0M) | [#695](https://github.com/openssh/openssh-portable/pull/695) | Add missing mldsa44-ed25519 option description | ssh-keygen.c |
| `pr-697.bc` (3.0M) | [#697](https://github.com/openssh/openssh-portable/pull/697) | AIX: PAM enablement to set  options.use_pam based on AIX system autht… | openbsd-compat/port-aix.c, openbsd-compat/port-aix.h, platfo |
| `pr-698.bc` (3.0M) | [#698](https://github.com/openssh/openssh-portable/pull/698) | scp: avoid reconnecting to identical remote sources | scp.c |
| `pr-699.bc` (3.0M) | [#699](https://github.com/openssh/openssh-portable/pull/699) | openpty: mark inputs const | openbsd-compat/bsd-openpty.c, openbsd-compat/openbsd-compat. |
| `pr-700.bc` (3.0M) | [#700](https://github.com/openssh/openssh-portable/pull/700) | add auth-option.c in checkquote and own ssh.service and add sshd_confi | auth-options.c |
