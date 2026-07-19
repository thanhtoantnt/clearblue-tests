# cb-check incremental-persist — reproducibility artifacts

Bitcode baselines + recorded results + a bench harness for the **incremental
persist** feature of `cb-check` (FermatAnalyzer branch
`feature/incremental-persist-reuse`).

Goal: anyone with a built `cb-check` from that branch can clone this repo and
reproduce the store / incremental / scratch numbers, or add their own PR
bitcode and re-run.

Companion docs (in the FermatAnalyzer tree):

- `docs/cb-check-incremental-persist.md` — what the feature is / how it works
- `docs/producing-bitcode.md` — how the `.bc` files here were compiled
- `docs/cb-check-modes.md` — normal / store / pure-load modes

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
│   └── run_bench.sh          # store + inc-vs-scratch for every bc/<proj>/*.bc
├── bc/                       # committed bitcode (the reproducible anchors)
│   ├── curl/{old.bc,new.bc}
│   ├── git/{old.bc,new.bc}
│   ├── libuv/{old.bc,new.bc}
│   ├── darknet/{old.bc,new.bc}
│   ├── redis/{old.bc,new.bc}
│   └── openssl/{old.bc,new.bc}
└── results/                  # recorded runs (committed)
    ├── curl/summary.tsv      # 10-PR table
    ├── git/summary.tsv       # 20-PR table
    └── round2/summary.tsv    # libuv / darknet / redis / openssl (20 PRs each)
```

Each `bc/<proj>/old.bc` is the baseline (stored once). Every other `*.bc`
(`new.bc`, or a `pr-NNNN.bc` you add) is benched against that store.

> The committed `bc/` ships **old.bc + one new.bc per project** (one PR sample).
> The full per-PR tables in `results/` were produced by rebuilding a `new.bc`
> per PR from source (see *Reproducing the full per-PR tables* below).

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

```bash
git clone <this-repo> incremental-persist-bench
cd incremental-persist-bench

export CBC=$HOME/github/FermatAnalyzer/build/tools/cb-check/cb-check

# all projects (store + inc vs scratch on the committed new.bc samples)
./scripts/run_bench.sh

# one project only
ONLY=curl ./scripts/run_bench.sh

# tune parallelism / per-run timeout
NWORKERS=8 TIMEOUT=3600 ./scripts/run_bench.sh
```

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
| libuv   | ~3s   | 0.8k     | ~50k     | 20  | ~1s     | ~2s         | ~50%        | 17/20 |
| curl    | ~13s  | 2.3k     | ~218k    | 10  | ~5s     | ~10s        | ~53%        | 10/10 |
| darknet | ~142s | 1.0k     | ~122k    | 20  | ~43s    | ~80s        | ~47%        | 20/20 |
| redis   | ~122s | 6–7k     | ~540k    | 20  | ~46s    | ~81s        | ~46%        | 20/20 |
| git     | ~97s  | 14k      | ~977k    | 20  | ~54s    | ~57s        | ~6%         | 13/20 |
| openssl | ~99s  | 16k      | ~900k    | 20  | ~59s    | ~51s        | −16%        | 2/20  |

**Takeaways**

- **Small/medium** C (libuv, curl, darknet, redis): strong, consistent wins
  after one store.
- **Large** (~1M instructions, full `git` / OpenSSL libcrypto): feature is
  correct but often neutral/slower — fixed IR-prep cost + dirty-set explosion
  (thousands of functions when a shared header changes) can dominate.
- Best wins are on PRs with small dirty sets (a few functions). Worst cases are
  PRs that touch widely-included headers (dirty counts in the thousands).

Always re-measure on your own hardware; these are indicative, not a guarantee.

## How the `.bc` files were produced

Typed-pointer LLVM 15 bitcode via [gllvm](https://github.com/SRI-CSL/gllvm)
(`gclang` + `get-bc`). Exact recipes are in the FermatAnalyzer doc
`docs/producing-bitcode.md`. In short, for each project:

- configure with `CC=gclang`
- `CFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers'`
- build the library/binary, then `get-bc -o old.bc <artifact>`

The committed `old.bc` per project was built from the baseline commit shown in
each project's `summary.tsv` run. Reuse requires the **same** flags for store
and incremental; mismatched flags invalidate fingerprints.

## Reproducing the full per-PR tables

The committed `bc/` only has one `new.bc` per project. The recorded
`results/<proj>/summary.tsv` tables were produced by rebuilding a `new.bc`
**per PR** from source and benching each against the store. To reproduce a full
table:

1. Clone the upstream project at the baseline commit.
2. Build `old.bc` (recipe above) and copy it to `bc/<proj>/old.bc`.
3. For each PR: apply the PR, rebuild with **identical** flags, and save the
   bitcode as `bc/<proj>/pr-NNNN.bc`.
4. Re-run `./scripts/run_bench.sh ONLY=<proj>` — every `pr-*.bc` is benched
   against the single store automatically.

Example PR loop (sketch; needs `gh` + the project cloned):

```bash
git fetch origin pull/NNNN/head:pr-NNNN
# copy the PR's changed .c/.h onto the baseline tree, rebuild with gllvm, then:
get-bc -o bc/curl/pr-NNNN.bc path/to/libcurl.so
```

See the FermatAnalyzer doc `docs/cb-check-incremental-persist.md` for the
end-to-end recipe used for the curl (10 PR) and git (20 PR) sweeps.

## Caveats

- **Machine-dependent.** Wall times vary with CPU/RAM/load; compare the *shape*
  (incremental vs scratch ratio, dirty counts), not exact seconds.
- **Persist dirs are gitignored** (`persist/`). They are regenerated by the
  script and can be 0.1–5 GB each.
- **Large bitcode** (git/openssl/redis): each store needs several GB RAM and
  can take 1–2 min; a full sweep of all projects is long-running.
- **Bitcode is binary** (~155 MB total in `bc/`). For pushing to a remote,
  consider Git LFS for `bc/**/*.bc`.
- **PR applicability**: GitHub PRs that don't merge cleanly onto the baseline
  either fail to build or produce huge dirty sets — expected, not a bug.

## License / attribution

Bitcode here is derived from upstream open-source projects (curl, git, libuv,
darknet, redis, openssl) under their respective licenses. This repo only holds
compiled artifacts + measurement scripts for the FermatAnalyzer incremental-
persist feature.
