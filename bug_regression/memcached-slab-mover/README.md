# memcached `start_slab_maintenance_thread` leaks `t` on failure (`-ps-ml`)

Real-code TP anchor on committed `bc/memcached/old.bc` — the same role the
libyaml NPD case plays, for the ML checker.

`slabs_mover.c:768` allocates `struct slab_rebal_thread *t = calloc(...)`
and returns NULL on two failure paths without freeing it:

- `t->active_am == NULL` → `return NULL` at line 786
- `pthread_create(...) != 0` → `return NULL` at line 791

Both leak `t` (CWE-401). Verified by hand; present in upstream memcached.

A run that misses line 786 fails the gate. Extra ML findings on the same
bitcode are fine (the run compares this sink, not the full report):
`mcmc_connect`'s FDL report on the same bitcode is a known false positive
(FermatAnalyzer issue #277) and unrelated to this case.
