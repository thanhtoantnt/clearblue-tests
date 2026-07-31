# cb-check incremental-persist — reproducibility artifacts

Bitcode baselines + recorded results + a bench harness for the **incremental
persist** feature of `cb-check` (FermatAnalyzer branch
`feature/incremental-persist-reuse`).

Goal: anyone with a built `cb-check` from that branch can clone this repo and
reproduce the store / incremental / scratch numbers, or add their own PR
bitcode and re-run.

Companion docs (in this repo's `docs/`, also mirrored from the FermatAnalyzer tree):

- [`docs/cb-check-incremental-persist.md`](./docs/cb-check-incremental-persist.md) — what the feature is / how it works
- [`docs/producing-bitcode.md`](./docs/producing-bitcode.md) — how the `.bc` files here were compiled
- [`docs/building-cb-check.md`](./docs/building-cb-check.md) — how to build the `cb-check` analyzer itself (incl. the RTTI-enabled LLVM 15 it needs)
- [`docs/cb-check-modes.md`](./docs/cb-check-modes.md) — normal / store / pure-load modes
- [`docs/pr31-npa-global-impact.md`](./docs/pr31-npa-global-impact.md) — later: does PR #31 NPA formal-arg change move baseline `--ps-npd`?

- [`results/main-vs-perf-incremental-persist-optimize.md`](./results/main-vs-perf-incremental-persist-optimize.md) — head-to-head: **main (PR #15)** vs **`perf/incremental-persist-optimize`** (store / zero-dirty / PR / no-persist; nworkers=16)

## What it measures

For each project:

1. **Store** the baseline `old.bc` once: `cb-check -enable-build-seg-only -persist-dir=P old.bc`
2. **Incremental** on a changed `new.bc`: `cb-check -enable-build-seg-only -enable-incremental-persist -persist-dir=P new.bc`
3. **Scratch** on the same `new.bc` (no persist): `cb-check -enable-build-seg-only new.bc`

Incremental should be faster than scratch when few functions changed. The
difference is the feature's payoff.

## Repo layout

```
incremental-persist-bench/
├── README.md
├── scripts/
│   ├── build_pr_bc.sh        # regenerate per-PR bitcode -> bc/<proj>/pr-<NNNN>.bc
│   └── run_bench.sh          # store old.bc + inc-vs-scratch for every bc/<proj>/*.bc
├── bc/                       # committed bitcode (medium/small only)
│   ├── curl/{old.bc, pr-22328.bc, ...}
│   ├── libuv/{old.bc, pr-5193.bc, ...}
│   ├── darknet/{old.bc, pr-2657.bc, ...}
│   ├── libjpeg-turbo/, nghttp2/, libsodium/, ...
│   └── (no git / redis / openssl — too slow for routine runs)
└── results/                  # recorded runs (committed)
    ├── curl/summary.tsv
    └── round2/summary.tsv    # libuv / darknet / …
```

Each `bc/<proj>/` holds **one `old.bc`** (the stored baseline) and **many
`pr-<NNNN>.bc`** files — one bitcode per PR, each built by applying that PR's
source onto the baseline and recompiling with the identical gllvm flags.
`run_bench.sh` stores `old.bc` once, then benches **every** `pr-*.bc` against
that single store (incremental) and from scratch.

## Prerequisites

1. **cb-check** built from FermatAnalyzer branch
   `feature/incremental-persist-reuse` (needs the incremental-persist code).
   Build it once and point the script at the binary:

   ```bash
   export CBC=/path/to/FermatAnalyzer/build/tools/cb-check/cb-check
   ```

   The runs behind these results used commit `9858d47f`.
2. **coreutils `script`** (for TTY log capture). Present on Linux/macOS.
3. Disk: each store writes a `persist/<proj>/` of **0.1–5 GB** (regeneratable,
   gitignored). Build/scratch on the large projects needs several GB RAM.

## Quick start

### Option A — reproduce from committed bitcode (no rebuild)

If `bc/<proj>/` already contains `pr-*.bc` files, you can run the benchmark
directly:

```bash
git clone <this-repo> incremental-persist-bench
cd incremental-persist-bench

export CBC=$HOME/github/FermatAnalyzer/build/tools/cb-check/cb-check

# all projects (store old.bc, then inc vs scratch on every pr-*.bc)
./scripts/run_bench.sh

# one project only
ONLY=curl ./scripts/run_bench.sh
```

### Option B — regenerate per-PR bitcode from source, then bench

```bash
# 1. clone the upstream sources into ~/clearblue/local-tests/{curl,git,...}
#    (see build_pr_bc.sh header for the list)

# 2. rebuild each PR's bitcode into bc/<proj>/pr-<NNNN>.bc
#    (needs network: git-fetches each PR ref from github)
./scripts/build_pr_bc.sh curl        # one project
./scripts/build_pr_bc.sh all         # every project
PRS="22328 22326" ./scripts/build_pr_bc.sh curl   # specific PRs

# 3. bench them
ONLY=curl ./scripts/run_bench.sh
```

Tune with `NWORKERS=8 TIMEOUT=3600 ./scripts/run_bench.sh`.

### Comparing two branches (A/B)

To compare `main` vs a perf branch on the incremental feature, build both
`cb-check` binaries and run the A/B harness. It stores `old.bc` once per
branch, then runs incremental on each `pr-*.bc` (the real workflow — **store
once, reuse**), and reports store + per-PR median for both:

```bash
MAIN=/tmp/cb-check-main PERF=/tmp/cb-check-perf ./scripts/ab_branches.sh
python3 scripts/ab_summarize.py /tmp/ab2.tsv
```

See [`docs/ab-branch-comparison.md`](./docs/ab-branch-comparison.md) for the
methodology (what to measure, what to skip, and the store-once rule that keeps
the run to ~1 hour instead of ~3.5).

Output goes to `results/<proj>/summary.tsv` (+ `store.log`, `inc_*.log`,
`scr_*.log`). The script prints each summary at the end.

### Result columns

| Column | Meaning |
|--------|---------|
| `sample` | bitcode name (`new`, or a PR number) |
| `store_s` | wall seconds to store `old.bc` once |
| `inc_s` / `scratch_s` | wall seconds for incremental / scratch on the sample |
| `body_dirty` | functions whose IR body fingerprint changed |
| `callers` | one-hop callers of body-dirty functions (also rebuilt) |
| `total_dirty` | body + callers |
| `inc_seg` / `scr_seg` | SEG-building phase time from the log |
| `status` | `ok` if both runs exited 0 |

A good incremental run shows `inc_s < scratch_s` and a low `total_dirty`.

## Recorded results (one machine, `-nworkers=16`, SEG-build only)

Bitcode produced with LLVM 15 + typed pointers (`-Xclang -no-opaque-pointers`)
via gllvm; all `-O0 -g`. Store time and one full per-PR sweep per project.

| Project | Store | SEGs (≈) | Inst (≈) | PRs | Avg inc | Avg scratch | Med speedup | Wins |
|---------|------:|---------:|---------:|----:|--------:|------------:|------------:|-----:|
| libssh2 | ~7s | ~1.2k | ~moderate | 8 | ~2s | ~6s | **~65%** | **8/8** |
| nghttp2 | ~3s | ~0.5k | ~small | 8 | ~1s | ~4s | **~75%** | **8/8** |
| memcached | ~8s | 0.6k | ~15k | 5 | ~2s | ~5s | ~60% | 5/5 |
| wolfssl | ~16s | 2.1k | ~160k | 12 | ~4s | ~11s | **~64%** | **12/12** |
| zstd | ~205s | 1.5k | ~300k | 12 | ~39s | ~130s | **~71%** | **12/12** |
| openssh | ~14s | 1.8k | ~75k | 11 | ~3s | ~8s | ~62% | 11/11 |
| mbedtls | ~3s | 0.8k | ~25k | 9 | ~1s | ~2s | ~50% | 9/9 |
| libevent | ~4s | 0.7k | ~30k | 12 | ~1s | ~2s | ~50% | 12/12 |
| c-ares  | ~5s   | 1.0k     | ~40k     | 9   | ~1s     | ~3s         | **~67%**    | **9/9**  |
| libuv   | ~3s   | 0.8k     | ~50k     | 20  | ~1s     | ~2s         | ~50%        | 17/20 |
| curl    | ~13s  | 2.3k     | ~218k    | 10  | ~5s     | ~10s        | ~53%        | 10/10 |
| darknet | ~142s | 1.0k     | ~122k    | 20  | ~43s    | ~80s        | ~47%        | 20/20 |

**Takeaways**

- **Small/medium** C (libuv, curl, darknet, …): strong, consistent wins after
  one store.
- Best wins are on PRs with small dirty sets (a few functions). Worst cases are
  PRs that touch widely-included headers (dirty counts in the thousands).
- **Dropped from the suite:** `git`, `redis`, `openssl` (multi-hour full NPD
  store/load; keep local if you need scale stress tests).

Always re-measure on your own hardware; these are indicative, not a guarantee.

## How the `.bc` files were produced

Typed-pointer LLVM 15 bitcode via [gllvm](https://github.com/SRI-CSL/gllvm)
(`gclang` + `get-bc`). Exact recipes are in [`docs/producing-bitcode.md`](./docs/producing-bitcode.md).
In short, for each project:

- configure with `CC=gclang`
- `CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers'`
- build the library/binary, then `get-bc -o old.bc <artifact>`

The committed `old.bc` per project was built from the baseline commit shown in
each project's `summary.tsv` run. Reuse requires the **same** flags for store
and incremental; mismatched flags invalidate fingerprints.

## Reproducing the per-PR tables

The committed `results/<proj>/summary.tsv` tables were produced by rebuilding a
bitcode **per PR** and benching each against the store. To reproduce:

```bash
# needs the upstream sources cloned (Option B above) + network to fetch PR refs
./scripts/build_pr_bc.sh <project>     # -> bc/<project>/pr-<NNNN>.bc for every PR in results/
ONLY=<project> ./scripts/run_bench.sh  # stores old.bc, benches each pr-*.bc
```

`build_pr_bc.sh` reads the PR list straight from the committed `summary.tsv`
(`results/<proj>/` for curl/…, `results/round2/` for the others), so it
reproduces exactly the PRs in the recorded tables. A few notes:

- It fetches each PR ref over SSH (`git fetch origin pull/NNNN/head`) and reads
  the changed `.c/.h` from `git diff` — **no GitHub API needed**.
- PRs that don't apply cleanly or don't build are skipped (logged as fail); the
  recorded tables already dropped those.
- `darknet` round-2 includes `syn0..syn8` entries (synthetic no-op edits used
  when real darknet PRs didn't apply); `build_pr_bc.sh` reproduces those via
  `synthetic_touch`.
- It is **resumable**: a `pr-*.bc` that already exists is skipped.

See [`docs/cb-check-incremental-persist.md`](./docs/cb-check-incremental-persist.md) for the
end-to-end recipe used for the curl (and other) PR sweeps.

## Caveats

- **Machine-dependent.** Wall times vary with CPU/RAM/load; compare the *shape*
  (incremental vs scratch ratio, dirty counts), not exact seconds.
- **Persist dirs are gitignored** (`persist/`). They are regenerated by the
  script and can be 0.1–5 GB each.
- **Bitcode is binary** (Git LFS for `bc/**/*.bc`). A full sweep of remaining
  projects is still multi-hour if you run full `--ps-npd` (not SEG-only).
- **PR applicability**: GitHub PRs that don't merge cleanly onto the baseline
  either fail to build or produce huge dirty sets — expected, not a bug.

## License / attribution

Bitcode here is derived from upstream open-source projects (curl, libuv,
darknet, libjpeg-turbo, …) under their respective licenses. This repo only
holds compiled artifacts + measurement scripts for the FermatAnalyzer
incremental-persist feature.
