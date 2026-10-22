# `bc/uaf-wrapper-memcpy/` — PR #180 review

Typed-pointer LLVM 15 bitcode for the two holes in the free-wrapper UAF
review. `old.bc` is local (`*.bc` is gitignored).

## Shapes

| function | source | what a correct report is |
|---|---|---|
| `copy_freed` | CWE-416: `free(p); memcpy(dst, p, 8)` | memcpy source of a freed byte buffer is a use |
| `free_rr` / `use_after` | [unbound `delfunc(void *)`](https://github.com/NLnetLabs/unbound/blob/master/edns-subnet/subnetmod.c) casts `void *` and frees a field; [kcat `buf_destroy`](https://github.com/edenhill/kcat/blob/master/input.c) frees `b->buf` | caller use of that field after the wrapper |

`clang-15 -O0` lowers `free_rr` to `bitcast i8*` then `getelementptr` of
`msg.rr`. The wrapper summary strips that bitcast and the caller replay
starts at the bitcast actual, so the field load is not re-materialized.

## Measured

`fermat-check` rebuilt from `tengiz-fix-issue168` @ `1d87598c`, compared
with the pre-patch binary:

| function | pre-patch | branch |
|---|---|---|
| `copy_freed` | reported | 0 |
| `use_after` | 0 | 0 |

`copy_freed` is the memcpy-source regression. `use_after` is not a clean
replay witness: its use is also `memcpy`. A typed `struct msg *` wrapper
followed by `m.rr[0]` is reported on the branch; the `void *` wrapper
with the same load is not.

```bash
./scripts/build_uaf_wrapper_memcpy_bc.sh
./scripts/check_uaf_wrapper_memcpy.py /path/to/fermat-check
```
