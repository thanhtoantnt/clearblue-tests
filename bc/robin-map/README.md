# `bc/robin-map/` — aggregate-return statistic name

Typed-pointer LLVM 15 bitcode for one `tsl::robin_map::insert`. The largest
function, `insert_impl_with_hash`, returns `{ bucket_entry*, i8 }` and is used
only by a `call`. `AggregateReturnDemotionPass` erases it after
`CBStatistics` has stored the `Function*`.

Unfixed `fermat-check` keeps the instruction count and writes a different
`FuncWithMostInst` than the pre-pass stdout line. The snapshot on
`fix/report-cbstatistics-uaf` (PR #252) makes the two names match.

## Layout

- **`use_robin.cpp`** — the driver.
- **`old.bc`** — local only (`*.bc` is gitignored). Rebuild with the script below.
- Upstream headers are cloned into `src/robin-map` and are not committed.

## Build

| | |
|---|---|
| Upstream | [Tessil/robin-map](https://github.com/Tessil/robin-map) |
| Pin | `91362aab` ("Rename functions to `*_with_hash`") |
| Toolchain | `clang-15 -O0 -g -fPIC -Xclang -no-opaque-pointers -std=c++17` |

```bash
./scripts/build_robin_map_bc.sh
./scripts/check_robin_map_stat_name.py /path/to/fermat-check
```
