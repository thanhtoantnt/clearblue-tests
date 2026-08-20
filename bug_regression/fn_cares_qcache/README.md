# FN: `-ps-ml` misses c-ares qcache entry leak

Ground-truth leak that `fermat-check -ps-ml` does **not** report.

| | |
|---|---|
| Project | c-ares |
| Fix | [`299bd617`](https://github.com/c-ares/c-ares/commit/299bd617c2ab5bb86cae0cbee25d48c29780a3ef) *Fix memory leak of qcache entry on key allocation failure* |
| Buggy parent | `d4bd20cc` |
| File | `src/lib/ares_qcache.c` `ares_qcache_insert_int` |
| Checker | `-ps-ml` |
| Run | 2026-08-19, FermatAnalyzer `main`, 248s, `-nworkers=8` |
| Result | **ML = 0**. 31 NPD (unrelated `ares_array_at` FPs). |

## Bug

```c
entry = ares_malloc_zero(sizeof(*entry));
if (entry == NULL)
  goto fail;
entry->key = ares_qcache_calc_key(qreq);
if (entry->key == NULL)
  goto fail;                 /* OOM after entry is live */
fail:
  if (entry != NULL && entry->key != NULL) {
    ares_free(entry->key);
    ares_free(entry);        /* skipped when key is NULL → leak */
  }
```

Fix: free `entry` whenever it is non-NULL.

## Reproduce

```bash
cd ~/clearblue/incremental-persist-bench
git submodule update --init src/c-ares
git -C src/c-ares checkout --detach d4bd20cc

# same gllvm flags as docs/producing-bitcode.md
export PATH="$HOME/go/bin:$HOME/tools/llvm15-official/bin:$PATH"
export LLVM_COMPILER_PATH=$HOME/tools/llvm15-official/bin
cmake -S src/c-ares -B /tmp/fn-cares-qcache -G Ninja \
  -DCMAKE_C_COMPILER=gclang \
  -DCMAKE_C_FLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers' \
  -DCMAKE_BUILD_TYPE=Debug -DCARES_SHARED=ON -DCARES_STATIC=OFF
ninja -C /tmp/fn-cares-qcache
getbc-link /tmp/fn-cares-qcache/lib/libcares.so.2.19.4 -o /tmp/fn-cares-qcache.bc

$CBC -ps-ml -omit-no-dbginfo -nworkers=8 \
  -report=/tmp/fn-cares-qcache.json /tmp/fn-cares-qcache.bc
# expect: TotalBugs==0 for Memory Leak

git -C src/c-ares checkout --  # back to the pin
```

(`get-bc` is broken on this host; `getbc-link` is the drop-in.)

## Resolution — no analyzer change needed

`fermat-check` already supports user-defined memory specs (`-load-memory-spec`,
see `lib/Language/Spec/Memory.cpp`). `mem-spec.json` in this folder teaches it
the c-ares wrappers:

```json
{
  "mem-alloc": ["ares_malloc", "ares_malloc_zero", ...],
  "mem-free":  {"ares_free": [0], "ares_realloc": [0]},
  "mem-alloc-size-arg": {"ares_malloc": [0], ...}
}
```

Run with it:

```bash
$CBC -ps-ml -omit-no-dbginfo -nworkers=8 \
  -load-memory-spec=bug_regression/fn_cares_qcache/mem-spec.json \
  -report=/tmp/fn-cares-qcache.json /tmp/fn-cares-qcache.bc
```

Verified on stock `main` (`82a6f5a5`) — **no FermatAnalyzer code change**:

| bitcode | ML | qcache leak at `ares_qcache_insert_int`? |
|---|---|---|
| buggy `d4bd20cc` | 46 | **reported** (sink `:374`) |
| fixed pin `589b5887` | 43 | not reported |

## Not in the TP gate

`suite.json` only lists must-find TPs on committed `old.bc`. This leak is **fixed** at the c-ares pin (`589b5887`), so it cannot be a TP on `bc/c-ares/old.bc`. Keep it here as an FN repro, not a harness case.
