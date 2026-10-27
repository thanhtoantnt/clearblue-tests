# fdl-loop-break

False-positive gate for issue #277 (FermatAnalyzer).

`mcmc_connect` walks an addrinfo cursor: the loop header tests
`next != NULL`, a successful `connect` `break`s out, and the post-loop
`if (next == NULL)` error return was reported as a file-descriptor leak.
The break edge preserves the header's non-null cursor, so that null test
is infeasible. The feasible continuation (non-null side) stores the
socket into the caller's context before returning.

`not_a_leak` is that shape and must stay quiet. `saved_by_callback` is
the same shape with the descriptor passed to an indirect call; that is
a handoff and must stay quiet. `real_leak_on_break` returns without
releasing on the feasible side. `leak_after_unrelated_call` calls an
unrelated function there and then returns with the descriptor open;
that call is not a release. `real_leak_on_normal_exit` leaks on the
loop's normal exit. All three must still be reported.

```
./build.sh
fermat-check --ps-fdl --report=out.json fdl_loop_break.bc
python3 ../../scripts/check_fdl_loop_break.py out.json
```
