# A/B: main vs feat/psa-summary-persist-opt (FULL, 16 projects)

**Date:** 2026-07-24
**Branches:** `main` @ `5d734a77` vs `feat/psa-summary-persist-opt` @ `b8a62146`
**Mode:** build-seg-only (primary use case — PSA code never runs)
**194 PR samples across 16 projects**

## Result: NO REGRESSION

Store total: 841s (main) vs 815s (feat) = **-3.2%** (noise)
Incremental median: 3.0s both branches. Perf wins 137/194 sorted-pair (71%).

## Store (one-time setup)

| project | main | feat | Δ |
|---------|------|------|---|
| c-ares | 4s | 3s | -18% |
| curl | 14s | 15s | +5% |
| darknet | 105s | 103s | -2% |
| git | 168s | 148s | -12% |
| libevent | 2s | 2s | +1% |
| libjpeg-turbo | 63s | 65s | +4% |
| libssh2 | 6s | 6s | -2% |
| libuv | 6s | 4s | -20% |
| mbedtls | 5s | 5s | -3% |
| memcached | 7s | 7s | -2% |
| nghttp2 | 3s | 3s | -1% |
| openssh | 13s | 14s | +5% |
| openssl | 138s | 138s | 0% |
| redis | 146s | 144s | -2% |
| wolfssl | 18s | 16s | -8% |
| zstd | 136s | 133s | -2% |
| **TOTAL** | **841s** | **815s** | **-3.2%** |

## Incremental (per-PR median)

All within ±6% (noise). Perf wins 137/194 sorted-pair.

## Correctness (full-analysis round-trip, 3-function case)

Store old.bc → incremental new.bc (1 function changed):
- SEG builder detects body-dirty: 1 (only the changed function)
- Changed function: recomputed + re-stored (checksum changed ✓)
- Unchanged functions: loaded + skipped (checksums identical ✓)

## Pre-existing issues (not caused by this branch)

- git/openssl: some PRs fail incremental load with rc=2 (SEG deserialization
  exception). Affects BOTH main and feat equally. Pre-existing SEG-load bug.
- Harness fix applied: snapshot store dir before each PR (incremental mode
  writes back rebuilt SEGs, contaminating the next PR's load without it).
