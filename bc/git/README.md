# `bc/git/` — git bitcode for cb-check incremental-persist
This folder holds typed-pointer LLVM 15 bitcode for **git**, used as the input for the `cb-check` incremental-persist benchmark (`scripts/run_bench.sh`).
## Layout
- **`old.bc`** — the stored baseline. Produced from the upstream source at commit [`55526a1826`](https://github.com/git/git/commit/55526a1826). `run_bench.sh` stores SEGs from this once; everything else is benchmarked against it.
- **`pr-<NNNN>.bc`** — one bitcode per pull request. Each was produced by applying that PR's source onto the baseline commit and recompiling with the **identical** flags used for `old.bc`. (Names with `pr-syn<N>.bc` are synthetic no-op edits, not real PRs.)
## Build configuration
| | |
|---|---|
| Upstream | `git/git` (<https://github.com/git/git>)
| Baseline commit | `55526a1826`
| Artifact extracted | `git (the single monolithic binary)`
| Toolchain | gllvm `gclang` + `get-bc`, LLVM 15, `-Xclang -no-opaque-pointers`
| Result size | `git binary (~977k inst)`
```bash
# how each .bc was built (same for old.bc and every pr-*.bc)
make CC=gclang CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' NO_OPENSSL=1 NO_CURL=1 NO_EXPAT=1 NO_GETTEXT=1 git
get-bc -o <file>.bc <artifact>
```
See [`docs/producing-bitcode.md`](../../docs/producing-bitcode.md) for the full recipe.
## Files in this folder (21 total)
| File | PR / source | Title | Changed C/C++ files |
|------|-------------|-------|---------------------|
| `old.bc` (29M) | baseline `55526a1826` | — | — |
| `pr-2297.bc` (29M) | [#2297](https://github.com/git/git/pull/2297) | Implement Ace Sequencer, git ace status, and git ace repair | builtin/ace.c |
| `pr-2299.bc` (29M) | [#2299](https://github.com/git/git/pull/2299) | daemon: fix network address handling bugs | daemon.c |
| `pr-2300.bc` (29M) | [#2300](https://github.com/git/git/pull/2300) | daemon: fix network address handling bugs | daemon.c |
| `pr-2301.bc` (29M) | [#2301](https://github.com/git/git/pull/2301) | remote: qualify "git pull" advice for non-upstream branches | remote.c |
| `pr-2302.bc` (29M) | [#2302](https://github.com/git/git/pull/2302) | config: suggest the correct form when key contains "=" | builtin/config.c, config.c, config.h |
| `pr-2303.bc` (29M) | [#2303](https://github.com/git/git/pull/2303) | connected: close err_fd in promisor fast-path | connected.c |
| `pr-2306.bc` (29M) | [#2306](https://github.com/git/git/pull/2306) | stash: reuse cached index entries in --patch temporary index | builtin/stash.c |
| `pr-2317.bc` (29M) | [#2317](https://github.com/git/git/pull/2317) | worktree: copy-on-write creation and shared-branch worktrees | builtin/worktree.c, copy.c, copy.h |
| `pr-2330.bc` (29M) | [#2330](https://github.com/git/git/pull/2330) | rebase: mention --abort when an exec step fails | sequencer.c, wt-status.c |
| `pr-2331.bc` (29M) | [#2331](https://github.com/git/git/pull/2331) | branch/push: suggest intended form when remote/branch slip given | advice.c, advice.h, builtin/branch.c, builtin/push.c |
| `pr-2332.bc` (29M) | [#2332](https://github.com/git/git/pull/2332) | clone: accept DEPTH env var as fallback for --depth | builtin/clone.c |
| `pr-2333.bc` (29M) | [#2333](https://github.com/git/git/pull/2333) | clone: accept `GIT_CLONE_DEPTH` env var as fallback for `--depth` | builtin/clone.c |
| `pr-2334.bc` (29M) | [#2334](https://github.com/git/git/pull/2334) | commit: preserve commit hash on a no-op amend | builtin/commit.c |
| `pr-2335.bc` (29M) | [#2335](https://github.com/git/git/pull/2335) | bisect: add --auto-reset to leave when done | bisect.c, builtin/bisect.c |
| `pr-2336.bc` (29M) | [#2336](https://github.com/git/git/pull/2336) | fetch: skip prune walk without refspec destinations | remote.c |
| `pr-2337.bc` (29M) | [#2337](https://github.com/git/git/pull/2337) | history: add squash subcommand to fold a range | advice.c, advice.h, builtin/history.c, sequencer.c, sequence |
| `pr-2341.bc` (29M) | [#2341](https://github.com/git/git/pull/2341) | config: reject keys with an empty subsection | builtin/config.c |
| `pr-2353.bc` (29M) | [#2353](https://github.com/git/git/pull/2353) | unpack-trees: avoid quadratic index scan in next_cache_entry() | unpack-trees.c |
| `pr-2355.bc` (29M) | [#2355](https://github.com/git/git/pull/2355) | Add code | builtin/checkout.c |
| `pr-2356.bc` (29M) | [#2356](https://github.com/git/git/pull/2356) | mv: report missing destination leading directory | builtin/mv.c |
