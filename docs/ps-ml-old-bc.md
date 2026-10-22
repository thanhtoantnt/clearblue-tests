# `-ps-ml` on `old.bc` (15 projects)

Run date: 2026-10-22. Analyzer: FermatAnalyzer `main` @ `b67dbd0a`
(merge of PR #256). LLVM 15 build. Default execution mode (`normal`).

```
fermat-check --hide-progress-bar -nworkers=12 -ps-ml -omit-no-dbginfo \
  -report=... bc/<proj>/old.bc
```

JSON reports were not committed. This note is the record.

## Counts

| project | bugs | secs |
|---|---:|---:|
| c-ares | 0 | 17 |
| curl | 0 | 36 |
| darknet | 98 | 11 |
| libevent | 0 | 8 |
| libexpat | 0 | 14 |
| libjpeg-turbo | 1 | 46 |
| libsodium | 0 | 18 |
| libssh2 | 0 | 93 |
| libuv | 0 | 18 |
| libyaml | 11 | 53 |
| mbedtls | 0 | 10 |
| memcached | 5 | 31 |
| nghttp2 | 0 | 34 |
| openssh | 1 | 31 |
| unbound | 6 | 44 |
| **total** | **122** | |

Nine projects report nothing. That is not a cleanliness result. Those
libraries allocate through wrappers (`ares_malloc`, `mbedtls_calloc`,
`uv__malloc`, curl's `curlx_*`) that this run did not turn into sources, or
they free what the checker does see.

## False positives

**libyaml, 11/11.** Scanner `STRING_INIT` / `yaml_malloc` results are
`STRING_DEL`'d on both exits or moved into the token
(`yaml_parser_scan_{block,flow,plain}_scalar`). `yaml_parser_initialize`
stores into the parser argument. `yaml_parser_process_directives` writes
`version_directive` through `*version_directive_ref` or `yaml_free`s it.
`yaml_document_initialize` pushes both `yaml_strdup` results onto the tag
stack. Traces stop at the allocator call (2 steps). An unfinished search is
still reported: `-psa-restrict-inter-search` is 200 in `normal` mode, and a
source whose walk hits that cap is reported as a leak.

**libjpeg-turbo, 1/1.** `jinit_memory_mgr` (`jmemmgr.c:1226`).
`jpeg_get_small` is published with `cinfo->mem = &mem->pub` and released by
`self_destruct`. Not a leak.

**openssh, 1/1.** `vdollar_percent_expand` (`misc.c:1453`). After a
successful `sshbuf_dup_string`, `*parseerror = 0` and the function returns
`ret`. The reported arm is `return *parseerror ? NULL : ret` taking the NULL
side. That side is dead once the assignment has run. `fatal_f` does not
return.

**unbound `worker_init`, 1.** `sldns_buffer_new` is stored in
`worker->env.scratch_buffer` and freed by `worker_delete` (`worker.c:2502`).
Failure calls `worker_delete` immediately. The trace stops at the call.

**unbound `fr_construct_from_config`, 5 reports at the create calls.** Each
pointer is stored into `ct` on that line (`ct->tcl`, `ct->auth_zones`,
`ct->fwds`, `ct->hints`, `ct->local_zones`). Allocation failure calls
`fr_construct_clear`. The reported witness does not reach a missing free.
Separate from these reports: `if (fr_poll_for_quit(fr)) return 1` after a
successful store does **not** clear `ct`. That is a real leak. These five
reports do not describe it.

**memcached, 1 of 5.** `main:5224` is the `return 1` of option `-N`, which
is textually before `slab_sizes_unparsed = strdup` at 5429. The trace still
walks 5429 then 5224. That edge is from switch lowering, not a source path.
The strdup itself is a real leak (next section).

**darknet `stb_image.h`, the TGA reports.** `stbi__tga_load` frees
`tga_palette` at 5618–5620 and returns `tga_data`. The reports stop on the
success side of `if (!tga_palette)` / `stbi__getn`, before that free.

## True positives

**memcached, 4.**

- `main:4902`. `storage_init_config` fails and `main` returns 1 without
  `free(meta)`. Other exits free it (4880, 6078, 6253).
- `main:5429`. `slab_sizes_unparsed = strdup(...)` is parsed in place and
  never freed. The copy in `meta->slab_config` is a second allocation.
- `start_slab_maintenance_thread:786`. `pthread_create` fails and the
  function returns NULL without freeing `t` (or `t->active_am`).
- `storage_init_config` result kept in `storage_cf`. `storage_init` uses the
  struct and does not free it. No `free(storage_cf)` in `memcached.c`.
  Process-lifetime leak. The witness is a line-0 switch leaf, so the path is
  low quality, but the missing free is real.

**darknet examples, 84 reports outside `stb_image.h`.** Drivers
(`validate_*`, `train_*`, `run_*`, `engine_go`, `change_leaves`) `calloc`
paths, labels, thread arrays, nets, and GPU lists and return or exit without
freeing them. `utils.c:shuffle` `calloc`s a swap buffer and returns without
`free`. These are real leaks. They are also process-lifetime leaks in
short-lived example programs, not use-after-return bugs.

**darknet `stb_image.h` GIF, qualified.** `stbi__gif_load_next` stores the
three buffers in `g->out`, `g->background`, `g->history`. If `g->out` is
NULL it returns without freeing the other two, which were allocated first.
That error path is a real leak. The three reports are stamped on the
`stbi__malloc` calls, not on that return, so they are the right objects and
the wrong witness.

## Not classified line by line

The other `stb_image.h` reports (PSD, HDR, BMP, PIC,
`stbi__convert_format`) were not each walked to a free or a missing free.
TGA was. GIF was. Do not treat the remaining 9 image reports as settled.
