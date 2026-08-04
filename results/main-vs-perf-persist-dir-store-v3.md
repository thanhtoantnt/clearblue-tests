# A/B: main vs `perf/persist-dir-store-v3`

**Date:** 2026-07-28  
**main binary:** `/tmp/cb-check-main` built from `main` `SEGSwap.cpp` @ `16380334`  
**perf binary:** `/tmp/cb-check-perf` @ `f5bffee2` (`perf/persist-dir-store-v3`)  
**Flags:** `--hide-progress-bar -nworkers=16 -enable-build-seg-only`  
**Harness:** `scripts/ab_branches.sh` + store-only ×3  
**Bitcodes:** `bc/{c-ares,libuv,curl,darknet,openssl}/`  
**Raw TSV:** `results/main-vs-perf-persist-dir-store-v3.tsv`

## Perf branch changes (vs main)

| Change | File |
|--------|------|
| Skip per-SEG `createDirectory` in dump | `SEGSwap::serializeToStorage` |
| Cache `dir/seg/` path prefix | `getFilePath(..., "seg", F)` |
| Thread-local DenseMaps in body fingerprint | `functionBodyFingerprint` |

Correctness smoke: both dump **972** SEG + **972** `.fp` on `c-ares/old.bc`.

## Store (ab_branches, 1 run)

| Project | main | perf | Δ |
|---------|-----:|-----:|--:|
| c-ares | 3802 ms | 3704 ms | −3% |
| libuv | 5188 ms | 5228 ms | +1% |
| curl | 12682 ms | 14472 ms | +14% |
| darknet | 105498 ms | 111662 ms | +6% |
| openssl | 122103 ms | 128038 ms | +5% |
| **sum** | **249s** | **263s** | **+5.5%** |

## Store-only ×3 (median ms)

| Project | main med | perf med | Δ% | main runs | perf runs |
|---------|---------:|---------:|---:|-----------|-----------|
| c-ares | 3779 | 3759 | −0.5% | 3779, 3711, 3779 | 3797, 3744, 3759 |
| libuv | 6087 | 5931 | −2.6% | 6087, 5208, 6464 | 6226, 5891, 5931 |
| curl | 15722 | 15340 | −2.4% | 15722, 15954, 14928 | 15281, 16003, 15340 |
| darknet | 99449 | 103314 | **+3.9%** | 99449, 106679, 98553 | 103314, 98651, 106308 |
| openssl | 120733 | 122764 | **+1.7%** | 115808, 121363, 120733 | 123175, 119581, 122764 |

## Incremental (per-PR median, ab_branches)

| Project | #PRs | main | perf | Δ% | pair wins |
|---------|-----:|-----:|-----:|---:|----------|
| c-ares | 9 | ~1s | ~1s | ~0% | noise |
| libuv | 20 | ~0.9s | ~0.9s | +1% | noise |
| curl | 10 | ~3.5s | ~3.7s | +3% | noise |
| darknet | 18 | ~36s | ~36s | ~0% | ~tie |
| openssl | 18 ok / 1 fail both | ~39s | ~39s | +1% | noise |

openssl `pr-31933`: **both** fail `rc=2` (timeout/env; not branch-specific).

perf wins **28/75** sorted PR pairs (worse than coin flip → noise).

## Verdict

**Do not merge for speed.** Micro-opts are in the noise vs current `main` (already has PR #17 parallel dump + preload cache + fp v4). No reliable store or incremental win; some single-run stores looked slower (curl/darknet/openssl).

Keep branch only if you want the cleanup (drop redundant `createDirectory`); otherwise drop.
