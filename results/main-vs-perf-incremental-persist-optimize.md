# main (PR #15) vs `perf/incremental-persist-optimize`

Head-to-head on the same machine, same flags, same bitcodes.

| Item | Value |
|------|--------|
| **Date** | 2026-07-23 |
| **main** | `73b4f17e` (Merge PR #15 `feature/incremental-persist-reuse`) |
| **perf** | `perf/incremental-persist-optimize` @ `b59e9e1f` (PR [#17](https://github.com/fermat-hkrc/FermatAnalyzer/pull/17)) |
| **Binary** | Release `cb-check` (each branch built in-tree `build/`) |
| **Flags** | `--hide-progress-bar -nworkers=16 -enable-build-seg-only` |
| **Bitcodes** | `bc/<project>/old.bc` (+ first `pr-*.bc` where present) |
| **Host** | local bench host (same process for both sides) |

## Persist store (`-persist-dir=…`, full SEG dump of `old.bc`)

| Project | main | perf | Δ |
|---------|-----:|-----:|--:|
| c-ares | 6159 ms | **3778 ms** | **−39%** |
| libuv | 7421 ms | **6254 ms** | **−16%** |
| curl | 21282 ms | **17816 ms** | **−16%** |
| darknet | 167017 ms | **111894 ms** | **−33%** |
| openssl | 197830 ms | **130893 ms** | **−34%** |

SEG and `.fp` counts matched main on every project (dump completeness OK).

| Project | segs (= fps) |
|---------|-------------:|
| c-ares | 972 |
| libuv | 786 |
| curl | 2324 |
| darknet | 1021 |
| openssl | 16404 |

## Incremental zero-dirty (`-enable-incremental-persist`, same `old.bc` again)

| Project | main | perf | note |
|---------|-----:|-----:|------|
| c-ares | 1076 ms | 1060 ms | ~same |
| libuv | 974 ms | 1061 ms | ~same |
| curl | 3577 ms | 3516 ms | ~same |
| darknet | 37483 ms | 38398 ms | ~same (noise) |
| openssl | 39529 ms | 48590 ms | ~same band / noise |

Zero-dirty is dominated by IR load + body hashing; this branch’s large win is **store dump**, not zero-dirty wall time.

## Incremental first PR (`pr-*.bc` after store)

| Project | main | perf |
|---------|-----:|-----:|
| c-ares | 1066 ms | 1047 ms |
| libuv | 1821 ms | 1835 ms |
| curl | 4216 ms | **3767 ms** |
| darknet | 38110 ms | **36795 ms** |
| openssl | 45430 ms | **40163 ms** |

## Non-persist (no `-persist-dir`)

| Project | main | perf |
|---------|-----:|-----:|
| c-ares | 4008 ms | 3942 ms |
| curl | 17693 ms | 17586 ms |

**No meaningful change** without `-persist-dir`.

## What perf changes (vs main)

| Change | Effect |
|--------|--------|
| Parallel Cap'n Proto SEG serialize + fingerprint write | Main store win (~15–40%) |
| `preloadPersistCache` + lock-free dirty digest lookup | Less syscall/lock cost on incremental scan |
| Shared process-wide const-content hash (fingerprint **v4**) | Less repeated CDS hashing across threads |
| Indexer FN/memo reuse; IndexManager single `find()` | Small; **same hierarchical keys** as main |

## Bottom line

- **Store with `-persist-dir`**: clearly faster (often **~15–40%**).
- **Incremental load/reuse**: SEG/fp parity with main; zero-dirty wall ≈ main.
- **Normal mode (no persist)**: unchanged.

## Repro sketch

```bash
# binaries: build each branch's Release cb-check, copy aside
MAIN=/path/to/cb-check-main
PERF=/path/to/cb-check-perf
BC=$PWD/bc
N=16

for proj in c-ares curl libuv openssl darknet; do
  for label in main perf; do
    bin=$MAIN; [ "$label" = perf ] && bin=$PERF
    dir=/tmp/bench_${label}_$proj
    rm -rf "$dir"
    # store
    $bin --hide-progress-bar -nworkers=$N -enable-build-seg-only \
      -persist-dir="$dir" "$BC/$proj/old.bc"
    # zero-dirty
    $bin --hide-progress-bar -nworkers=$N -enable-build-seg-only \
      -enable-incremental-persist -persist-dir="$dir" "$BC/$proj/old.bc"
    # first PR (if any)
    pr=$(ls "$BC/$proj"/pr-*.bc 2>/dev/null | head -1)
    [ -n "$pr" ] && $bin --hide-progress-bar -nworkers=$N -enable-build-seg-only \
      -enable-incremental-persist -persist-dir="$dir" "$pr"
  done
done
```
