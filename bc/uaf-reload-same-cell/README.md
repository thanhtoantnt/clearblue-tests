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

`overlay_fp` is libevent's extra slot: `evbuffer_chain_file_segment` and
`evbuffer_multicast_parent` share one address. Same offset is not enough
when the loaded types are different structs.

## Run

```sh
CLANG=clang-15 ../scripts/build_uaf_reload_same_cell_bc.sh
python3 ../../scripts/check_uaf_reload_same_cell.py /path/to/fermat-check
```

`wrap_reload_ptr` is already reported by an unfixed analyzer; it stays in
the gate so the wrapper path is not dropped. The gate fails on an unfixed
analyzer because the four direct reloads are missing, and passes once all
five are reported and the four non-bugs are absent.
