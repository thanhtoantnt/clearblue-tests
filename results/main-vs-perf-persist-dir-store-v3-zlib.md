# A/B: main vs `perf/persist-dir-store-v3` (zlib SEG dump)

**Date:** 2026-07-28  
**main:** `/tmp/cb-check-main` @ main SEG I/O (raw packed Cap'n Proto)  
**perf:** `/tmp/cb-check-perf` @ branch tip (CBSEGZ1 + zlib `Z_BEST_SPEED`)  
**Flags:** `--hide-progress-bar -nworkers=16 -enable-build-seg-only`  
**Harness:** `scripts/ab_branches.sh` + store-only ×3  

## Changes under test

1. **SEG dump/load zlib** (`lib/Schema/seg_schema_impl.cpp`): write packed message to memory → `compress2(Z_BEST_SPEED)` → `CBSEGZ1` + u64 uncomp size + payload. Load auto-detects magic; legacy raw packed still works.
2. **Cold-store fingerprint**: skip `PersistCacheMu` when preload cache not ready.
3. Earlier micro-opts (seg path cache, skip per-SEG mkdir, TLS fingerprint maps).

## Disk (SEG files only, store-only first run)

| Project | main MB | perf MB | ratio |
|---------|--------:|--------:|------|
| c-ares | 266 | 31 | **12%** |
| libuv | 271 | 30 | **11%** |
| curl | 1071 | 125 | **12%** |
| darknet | 5462 | 545 | **10%** |
| openssl | 8684 | 955 | **11%** |

## Store wall (store-only ×3 median)

| Project | main | perf | Δ% |
|---------|-----:|-----:|---:|
| c-ares | 3811 | 3901 | +2.4% |
| libuv | 6153 | 6468 | +5.1% |
| curl | 15976 | 16282 | +1.9% |
| darknet | 105628 | 112967 | **+6.9%** |
| openssl | 118558 | 128125 | **+8.1%** |

## Store wall (ab_branches 1-run)

| Project | main | perf | Δ |
|---------|-----:|-----:|--:|
| sum 5 projects | 250s | 264s | **+5.3%** |
| openssl alone | 122s | 117s | −4% (noise vs ×3) |

## Incremental (per-PR median)

~parity (c-ares/curl/openssl slight noise either way; darknet +4%). perf wins 19/76 pairs.

## Verdict

| Metric | Result |
|--------|--------|
| **Persist dir size** | **Clear win (~9–10× smaller)** |
| **Store / incremental wall on this host (fast local disk)** | **No win; often +2–8% store** (zlib CPU > I/O savings) |

Use when disk / network FS / artifact size matters. **Do not claim wall-time speedup** on NVMe-class storage without further work (e.g. faster codec, async pipeline, or compress-only-above-size threshold tuned to I/O).
