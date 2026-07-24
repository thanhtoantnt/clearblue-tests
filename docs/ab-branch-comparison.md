# A/B branch comparison (main vs perf)

How to compare two `cb-check` builds (e.g. `main` vs a perf branch) on the
incremental-persist feature, the right way.

Related:

- [cb-check-incremental-persist.md](./cb-check-incremental-persist.md) — what the feature is
- [cb-check-modes.md](./cb-check-modes.md) — store / load / normal modes
- [`scripts/ab_branches.sh`](../scripts/ab_branches.sh) — the harness this doc describes

## The workflow the feature exists for

```
store old.bc ONCE  →  incremental on each pr-*.bc (reuse the store)
```

That's it. `-enable-incremental-persist` is a **store once, reuse many** feature:
you build + dump SEGs for a baseline once, then every PR that lands loads the
clean SEGs from disk and rebuilds only the dirty functions.

## What to measure (and what NOT to)

| mode | command | measures | use it? |
|------|---------|----------|---------|
| **store** | `cb-check -persist-dir=X old.bc` | one-time build + dump cost | ✅ |
| **incremental** | `cb-check -enable-incremental-persist -persist-dir=X pr-*.bc` | load clean + rebuild dirty — **the feature** | ✅ |
| `zero` (incremental on `old.bc` itself) | same flags, same `old.bc` | 0 dirty funcs → builds **nothing**; only the fingerprint scan loop | ❌ not real |
| `nopersist` / scratch (no `-persist-dir`) | `cb-check pr-*.bc` | full rebuild, no reuse | optional baseline |

`zero` re-analyzes the *exact same* `old.bc` that was just stored, so every
fingerprint matches and nothing rebuilds. Nobody runs that in practice; it only
isolates fingerprint-scan overhead. **Skip it** for branch comparisons — it adds
wall-time without representing real usage.

## The one rule that saves the most wall-time

**Store once, then run every PR against the same stored dir.** Do not re-store
before each PR run — the store is identical work each time (~120s on darknet),
and re-running it per-sample multiplies wall-time by ~6× for nothing.

```bash
# RIGHT: store once, reuse
$CBC -persist-dir=$X old.bc
for pr in bc/$proj/pr-*.bc; do
  $CBC -enable-incremental-persist -persist-dir=$X "$pr"
done

# WRONG: re-store before every run (wastes a full store each time)
for pr in bc/$proj/pr-*.bc; do
  rm -rf $X; $CBC -persist-dir=$X old.bc          # ← don't
  $CBC -enable-incremental-persist -persist-dir=$X "$pr"
done
```

## Running the comparison

### 1. Build both binaries

```bash
cd ~/github/FermatAnalyzer
# perf branch
git checkout perf/<branch>
cmake --build build --target cb-check -j$(nproc)
cp build/tools/cb-check/cb-check /tmp/cb-check-perf
# main
git checkout main
cmake --build build --target cb-check -j$(nproc)
cp build/tools/cb-check/cb-check /tmp/cb-check-main
git checkout perf/<branch>   # restore
```

### 2. Run the harness

```bash
MAIN=/tmp/cb-check-main PERF=/tmp/cb-check-perf \
  bash ~/clearblue/incremental-persist-bench/scripts/ab_branches.sh
```

It writes a TSV to `/tmp/ab2.tsv`:

```
branch   project   mode   sample   ms
main     darknet   store  old      111234
main     darknet   inc    pr-5193  35120
perf     darknet   store  old      106001
perf     darknet   inc    pr-5193  34200
```

Resumable: re-running skips combos already in the TSV. Filter projects with
`PROJECTS="darknet openssl"`.

### 3. Summarize

```bash
python3 scripts/ab_summarize.py /tmp/ab2.tsv
```

Reports store total + per-PR incremental median, per project, main vs perf.

## Cost

Single run per branch (store once + all PRs):

| tier | projects | ~time |
|------|----------|------:|
| small | c-ares, libuv, libssh2, mbedtls, nghttp2, memcached, libevent | ~1 min |
| medium | curl, libjpeg-turbo, wolfssl, openssh | ~10 min |
| large | darknet, zstd, redis, openssl, git | ~15 min each |

Full A/B (16 projects, both branches): **~1 hour**. The store-once rule is what
keeps it there — a naive re-store-per-run harness takes ~3.5 hours.

## Sanity rules

- **Same machine, same load, back-to-back.** Don't interleave with other builds.
- **Store from the same `old.bc`** for both branches (committed in `bc/`).
- **Confirm SEG/fp counts match** between branches on at least one project — a
  divergent dump means a behavior change, not a perf change.
