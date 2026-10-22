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

Pre-patch `fermat-check --ps-uaf` reports only `copy_freed` (`p` is the
2nd argument of `memcpy`). `use_after` is absent. The branch should
report both. Missing `copy_freed` is the memcpy-source regression.
Missing `use_after` is the replay miss.

```bash
./scripts/build_uaf_wrapper_memcpy_bc.sh
./scripts/check_uaf_wrapper_memcpy.py /path/to/fermat-check
```
