# Local field store is not a release (`ps-ml`, `ps-fdl`)

`b.p = malloc()` and `b.f = fopen()` were treated as handing the pointer
off, because the store pointer is a GEP. `b` dies with the frame, so the
pointer is leaked. A store into a caller object, a later free/fclose, and
passing `&b` to another function stay quiet.

No `src/` function in a quick scan has this exact non-escaping local-field
shape. The gate is the shape.

## Run

```sh
bc/local-field-leak/build.sh
python3 scripts/check_local_field_leak.py /path/to/fermat-check
```
