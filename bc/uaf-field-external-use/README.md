# UAF: freed field-derived pointer passed to an external call (`ps-uaf`)

Executable gate for the `UseAfterFree::isSrcSinkNotAlias` false negatives
(FermatAnalyzer `lib/Checker/PSA/Vulnerabilities/UseAfterFree.cpp`).

## The bug

When the freed SSA value flows into an **external or indirect** call,
`UseAfterFree::checkSite` asks
`isSrcSinkNotAlias(SrcInst /*free*/, useCall)` and suppresses the report
(`ST_Call` instead of `ST_Sink`) whenever it answers "not alias". Two
defects made that answer wrong whenever the freed pointer was **loaded
from memory** (a struct field or array element — `LoadInst` of a `GEP`):

1. **SSA value names, not callees.** The `CallInst`-vs-`CallInst` case
   compared `SrcCall->getName() == SinkCall->getName()`. The name of an
   unnamed LLVM instruction is `""`, so the test held for nearly every
   `(free, use)` pair — `free(p)` vs `strlen(p)` included — and the
   comparison recursed into the **first arguments of two unrelated
   calls**.
2. **Every GEP pair "not alias".** The `GEPOperator`-vs-`GEPOperator`
   case returned `true` unconditionally (the array-type check inside was
   dead code — both branches returned `true`), including for a value
   against **itself**.

Combined: `p = x->data; free(p); strlen(p)` was never reported, while the
byte-identical malloc-provenance shape (`p = malloc(n); free(p);
strlen(p)`) was. The suppression even keyed off the shape of an argument
the freed value never touched: `snprintf(x->buf, 32, "%s", p)` after
`free(p)` was suppressed because **arg0** (`x->buf`) is GEP-shaped, while
`snprintf(out, 32, "%s", p)` (plain parameter arg0) was reported.

Not affected: sinks that are plain dereferences (`p[0]`, `memset(p, …)`)
take the `SEGDereferenceSite` path in `checkSite` and are reported
regardless of provenance (`u1_malloc` / `u2_field`).

## The case

`uaf_field_use.c` holds eight genuine use-after-free functions:

| function | freed value provenance | sink | unfixed | fixed |
|----------|------------------------|------|---------|-------|
| `f_field` | field (`x->data`) | `strlen(p)` arg0 | **miss** | hit |
| `m2_arg0_gep` | field (`x->data`) | `snprintf(x->buf, …, p)` | **miss** | hit |
| `f_plain` | `malloc` | `strlen(p)` arg0 | hit | hit |
| `m3_malloc_gep` | `malloc` | `snprintf(x->buf, …, p)` | hit | hit |
| `m1_arg0_plain` | field | `snprintf(out, …, p)` (param arg0) | hit | hit |
| `f_field_deref` | field | `p[0]` deref | hit | hit |
| `u1_malloc` | `malloc` | `memset(p, 0, n)` | hit | hit |
| `u2_field` | field | `memset(p, 0, x->len)` | hit | hit |

## Why a synthetic case (and the cflow/ corpus scan)

A same-SSA `field → local → free → external call` shape does not occur in
any of the 17 `src/` projects as of 2026-10-23 (scanned with three
pattern matchers: field assignment, array-element assignment, adjacent
free/use). A/B runs of `-ps-uaf` over the committed
`bc/{libevent,memcached,c-ares}/old.bc` report 0 before and after the
fix, consistent with the scan. The real-world anchor for freed-field UAFs
is `bc/cflow/` (CVE-2020-23856) — a *different* FN class (cross-object
dangling list reference) that neither binary sees; see that directory.

## Run

```sh
CLANG=clang-15 ../scripts/build_uaf_field_use_bc.sh   # rebuild old.bc
python3 ../../scripts/check_uaf_field_use.py /path/to/fermat-check
```

The gate **fails** on an unfixed `fermat-check` (missing `f_field`,
`m2_arg0_gep`) and passes once the analyzer reports all eight.

Verified 2026-10-23: base (1.0-20261022-82ac0db6) → 6/8; fixed → 8/8.
`FermatAnalyzerRegressionTest` `base_test/uaf` stays 100 % with the fix.
