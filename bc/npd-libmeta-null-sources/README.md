# NPD: a "not found" NULL return is a null source (`ps-npd`)

`strchr`, `strstr`, and `fgets` were in the analyzer's null-return table,
but their mirrors with the same contract were not: `getenv`, `strrchr`,
`strpbrk`, `memmem`, `bsearch`, `getcwd`, `setlocale`. An unchecked
dereference of any of them was never a source, while the byte-identical
`strchr` shape was reported.

A scan of `src/` (curl, libevent, c-ares, memcached, libssh2) found no
unchecked deref of these: every use checks the return, which is why this
gate is the shape rather than a project sink. On `bc/{libevent,memcached,
libssh2,curl}` the fixed analyzer produces zero findings whose trace names
any of the new functions — the change costs nothing on real code.

## Run

```sh
bc/npd-libmeta-null-sources/build.sh
python3 scripts/check_npd_libmeta_null_sources.py /path/to/fermat-check
```
