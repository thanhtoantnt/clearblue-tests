# UAF: a later load of a freed cell (`ps-uaf`)

`free(m->rr); use(m->rr)` is two loads of one cell. After mem2reg they are
different SSA values, so the search from the free's operand never reaches
the use. `my_free(m->rr); use(m->rr)` has the same hole when `my_free`
frees its argument: the wrapper summary is installed on the actual load,
not on a later load of that cell.

## The case

| function | shape | unfixed | fixed |
|----------|-------|---------|-------|
| `reload_field` | `free(m->rr); memcpy(dst, m->rr)` | miss | hit |
| `reload_strlen` | `free(m->rr); strlen(m->rr)` | miss | hit |
| `double_reload` | `free(m->rr); free(m->rr)` | miss | hit |
| `use_before_null` | use, then `m->rr = NULL` | miss | hit |
| `wrap_reload_ptr` | `my_free(m->rr); memcpy(dst, m->rr)` | hit | hit |
| `killed_store` | `m->rr = NULL` before the use | absent | absent |
| `killed_memset` | `memset` of the object before the use | absent | absent |
| `other_index` | `free(a[0]); strlen(a[1])` | absent | absent |
| `overlay_fp` | two struct-pointer types at one offset | absent | absent |
| `branch_partial` | store on one arm, use at the join | miss | hit |
| `branch_else_use` | use on the arm that does not store | hit | hit |
| `branch_sibling` | store in the other arm; use does not reach it | hit | hit |
| `early_return_store` | store then `return`; use on the fallthrough | hit | hit |
| `branch_both_kill` | both arms store, then the use | absent | absent |
| `snapshot_then_store` | store between the snapshot and `free` | absent | absent |

`overlay_fp` is libevent's extra slot: `evbuffer_chain_file_segment` and
`evbuffer_multicast_parent` share one address. Same offset is not enough
when the loaded types are different structs.

`branch_partial` is the blocking hole: a store on one path must not drop
the use on the path that never stores. `branch_both_kill` is why "the
store must dominate the use" is the wrong fix. Neither store dominates
the join, and the use must stay unreported.

## Run

```sh
CLANG=clang-15 ../scripts/build_uaf_reload_same_cell_bc.sh
python3 ../../scripts/check_uaf_reload_same_cell.py /path/to/fermat-check
```

`wrap_reload_ptr`, `branch_else_use`, `branch_sibling`, and
`early_return_store` are already reported by an unfixed analyzer. The gate
fails on an unfixed analyzer because the direct reloads, including
`branch_partial`, are missing, and passes once every required function is
reported and the non-bugs are absent.
