# Local field store is not a release (`ps-ml`, `ps-fdl`)

`b.p = malloc()` and `b.f = fopen()` were treated as handing the pointer
off, because the store pointer is a GEP. `b` dies with the frame, so the
pointer is leaked. A store into a caller object, a later free/fclose, and
passing `&b` to another function stay quiet.

Positives: `leak_field`, `leak_calloc`, `leak_nested`, `leak_file`,
`leak_slot`. Quiets: store into a caller object, free/fclose, passing `&b`,
return by value, pass by value, and `*heap = local` (`copy_out`).

`src/` does not have the non-escaping leak. It does have the transfers this
must not call leaks: darknet `make_activation_layer` (sret), `copy_image`
(return by value), `read_tree` (`llvm.memcpy` of the local into a heap
object). Those three must stay at 0.

## Run

```sh
bc/local-field-leak/build.sh
python3 scripts/check_local_field_leak.py /path/to/fermat-check
python3 scripts/check_local_field_suite.py /path/to/fermat-check
```
