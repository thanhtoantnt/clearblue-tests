# cflow 1.6 — CVE-2020-23856 (use-after-free via `caller->callee`)

New real-world project added 2026-10-23 (found via web search for a
field-provenance UAF in a small C repo) as the real-code anchor for the
`bc/uaf-field-external-use/` work on the `-ps-uaf` checker.

## Provenance

GNU cflow 1.6 release tarball:
`https://ftp.gnu.org/gnu/cflow/cflow-1.6.tar.xz` (direct fetch; github
clones are blocked on this network). CVE-2020-23856 — "Use-after-Free
vulnerability in cflow 1.6 in `void call(char *name, int line)` at
`src/parser.c` … via the pointer variable `caller->callee`". The freed
object is a `Symbol` that stays linked in other symbols' `caller` /
`callee` linked lists after `delete_symbol()` (`src/symbol.c:196-207`)
frees it; later `data_in_list()` walks the dangling list from
`call()` (`src/parser.c:1284`).

## Rebuild `old.bc`

```sh
# from an extracted cflow-1.6 tree after CC=clang ./configure && make
# (make generates the gnulib headers the TUs include)
../../scripts/build_cflow_bc.sh /path/to/cflow-1.6
```

Each `src/*.c` is compiled `-O0 -g -fPIC -Xclang -no-opaque-pointers
-emit-llvm` with `-DHAVE_CONFIG_H -I. -Isrc -Ignu` (plus
`-DLOCALEDIR=… -DPACKAGE="cflow"` for `main.c`) and the `.bc` files are
`llvm-link`ed — same shape as every other `bc/<proj>/old.bc`.

## Result (2026-10-23, fermat-check 1.0-20261022-82ac0db6)

`-ps-uaf` reports **0** findings on `old.bc`, before **and** after the
`UseAfterFree::isSrcSinkNotAlias` fix gated by
`bc/uaf-field-external-use/`. The CVE site is a *different* false-negative
class than that fix: the dangling reference flows through a linked list
(`linked_list_append(&caller->callee, sp)` — a memory-flow edge between
two heap objects), while the SEG value-flow walker only connects the same
SSA value's uses. No same-SSA `field → local → free → external call`
shape exists anywhere in this codebase either (same scan as the other 17
projects), so the isSrcSinkNotAlias A/B on this project is 0 → 0.

This directory documents a **known gap**: a real, CVE-catalogued UAF that
the `-ps-uaf` checker does not see on real code. Turning it into an
executable gate needs inter-object field-sensitive flow through linked
containers — not a one-line `checkSite` fix.
