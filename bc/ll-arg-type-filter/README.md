# Lock leak: a caller-passed mutex is not irrelevant (`ps-ll`)

Gate for `LockLeak::isIrrelevantNode` in
`lib/Checker/PSA/Vulnerabilities/LockLeak.cpp`.

With `-ps-ll-enable-type-filter` (the default), an argument was treated as
irrelevant when `isLockType` was true. That is the opposite of the file
descriptor checker, which keeps an argument only when its type matches.
A `pthread_mutex_t *` parameter was dropped, so a lock of that parameter
never reached the unlock on the other branch.

`maybe` is that leak. `maybe_local` is the same control flow on a local
mutex and is reported either way. `ok` always unlocks and must not be
reported. `leak` has no unlock in the function; `-ps-ll-must-unlock-in-this-function`
drops it even after this fix, so it is not in the gate.

A scan of `pthread_mutex_lock` in `src/` did not find this shape: the
parameter locks (`uv_mutex_lock`, `threading_mutex_lock_pthread`) have no
unlock in the same function, so the must-unlock filter drops them either
way. libevent `--ps-ll` is 0. memcached's two reports are
`&maintenance_lock` and `&worker_hang_lock`, not this argument filter.

## Run

```sh
bc/ll-arg-type-filter/build.sh
python3 scripts/check_ll_arg_type_filter.py /path/to/fermat-check
```
