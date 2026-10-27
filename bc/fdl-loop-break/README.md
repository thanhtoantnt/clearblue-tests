# fdl-loop-break

False-positive gate for issue #277 (FermatAnalyzer).

`mcmc_connect` walks an addrinfo cursor: the loop header tests
`next != NULL`, a successful `connect` `break`s out, and the post-loop
`if (next == NULL)` error return was reported as a file-descriptor leak.
The break edge preserves the header's non-null cursor, so that null test
is infeasible. The feasible continuation (non-null side) stores the
socket into the caller's context before returning.

`not_a_leak` is that shape and must stay quiet. `real_leak_on_break` is
the same shape but the feasible continuation returns without releasing,
so it must still be reported. `real_leak_on_normal_exit` leaks on the
loop's normal exit and must still be reported.

```
./build.sh
fermat-check --ps-fdl --report=out.json fdl_loop_break.bc
python3 ../../scripts/check_fdl_loop_break.py out.json
```
