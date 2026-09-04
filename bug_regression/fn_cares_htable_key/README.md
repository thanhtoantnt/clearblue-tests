# FN: `-ps-ml` misses c-ares htable dict `bucket->key` leak

Ground-truth leak that `fermat-check -ps-ml` does **not** report (with or
without store-sink loosening).

| | |
|---|---|
| Project | c-ares |
| Fix | [PR #1105](https://github.com/c-ares/c-ares/pull/1105) / [`a34fbfb4`](https://github.com/c-ares/c-ares/commit/a34fbfb4c3283df0606b076d2c605fbbf5557b6f) *Fix memory leak of bucket->key in ares_htable_dict_insert error path* (issue #1104) |
| Buggy parent | `734878c1` (this folder's `buggy.bc`) |
| File | `src/lib/dsa/ares_htable_dict.c` `ares_htable_dict_insert` |
| Checker | `-ps-ml` + c-ares mem-spec (see `mem-spec.json`) |
| Result | **FN**: 342 ML reports, none at this sink |

## Bug

```c
bucket = ares_malloc_zero(sizeof(*bucket));
bucket->key = ares_strdup(key);       /* key now owned by bucket */
if (bucket->key == NULL)  goto fail;
if (val) { bucket->val = ares_strdup(val); if (!bucket->val) goto fail; }
if (!ares_htable_insert(htable->hash, bucket)) goto fail;
return ARES_TRUE;

fail:
  if (bucket) {
    ares_free(bucket->val);            /* key NOT freed on this path */
    ares_free(bucket);                 /* ← container freed, field leaks */
  }
```

Fix adds `ares_free(bucket->key)` at `fail:`.

## Why it is a checker design gap (measured, not guessed)

`MemoryLeak::checkSite` treats `store %p, gep %bucket` as **ST_Sink**
(`storedToSpecialCases`: any `GEPOperator` dest). That single predicate covers
both paths at once:

- insert succeeds → table owns `key` → sink, correct;
- fail path → `free(bucket)` without `free(key)` → still "sink", FN.

A/B experiment (`-ps-ml-store-sink-mode`, FermatAnalyzer branch
`toan-ml-fn-htable-dict-key`, buggy vs fixed bc, same mem-spec):

| mode | rule | buggy ML total | fixed ML total | `dict_insert` line-115 report |
|---|---|---:|---:|---|
| 1 (default) | GEP = sink | 342 | 342 | absent (FN) |
| 0 | GEP never sink | **665** | **668** | **present on both** |
| 2 | GEP recurses, heap-base not sink | **658** | **662** | **present on both** |

Loosening the rule roughly **doubles** module-wide ML and the new report at
line 115 fires on the **fixed** bitcode too (it is the success/`key==NULL`
path, not the leak). No local variant of the predicate separates buggy from
fixed.

## Required model

Field-sensitive ownership for containers allocated in the function:

- **escape** of the container (passed to a sink call, returned, stored to
  global/arg) sinks the field values;
- **`free(container)`** does **not** sink the fields — the leak surfaces iff
  the freeing path does not also free the field.

That is the same class as `xfer_set_masters` (issue #2 item 1): leak on an
error path after a maybe-escaping store. Not a `checkSite` one-liner.

## Reproduce

```bash
$CBC -ps-ml -omit-no-dbginfo -nworkers=16 \
  -load-memory-spec=bug_regression/fn_cares_htable_key/mem-spec.json \
  -report=/tmp/ml.json bug_regression/fn_cares_htable_key/buggy.bc
# expect: no report in ares_htable_dict_insert (lines ~115..136)
```

## Status

Documented FN. Not in `suite.json` (nothing finds it). Revisit when ML gains
field-sensitive container ownership.
