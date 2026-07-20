# Bug-finding demo: incremental persist catches a bug introduced by a PR

This folder proves the `-enable-incremental-persist` mode **finds bugs** — not
just builds SEGs faster. It contains one PR's bitcode with a deliberately
injected bug, plus the baseline, and the exact `cb-check` commands to catch it.

## Files in this folder

| File | What |
|------|------|
| `old.bc` | **Baseline** — darknet built from upstream commit `f6afaabc` (the same one used for `bc/darknet/old.bc`). No bug. |
| `pr-injected-npd.bc` | **The "PR"** — darknet rebuilt after adding one function with a null-pointer dereference (a security bug a real PR might introduce). |

## What the "PR" changes

The PR adds a single new function to `src/image.c`:

```c
int darknet_injected_npd_test(int x) {
  int *p = (int*)0;          // p is NULL
  if (x > 0) p = (int*)0;    // still NULL
  return *p;                 // ← dereference of NULL = CWE-476 / CWE-690
}
```

This is a textbook null-pointer dereference (NPD). It simulates a PR that
introduces a security bug. In real life this would be a bug accidentally
introduced by a contributor's change, not a deliberate injection.

The only source change vs. the baseline is those 2 lines in `src/image.c`:

```text
 src/image.c | 2 ++
 1 file changed, 2 insertions(+)
```

## How cb-check finds it (exact commands)

```bash
CBC=$HOME/github/FermatAnalyzer/build/tools/cb-check/cb-check
CHK="-segbuilder-aa=falconplus --ps-npd --enable-heap-alloc-failure --psa-enable-arg-symbol"

# 1) Store the clean baseline ONCE (writes ./persist/seg/ ... ~130s, one-time)
$CBC --hide-progress-bar -nworkers=16 -enable-build-seg-only \
     -persist-dir=./persist old.bc

# 2) Run incremental NPD check on the "PR" — reuses stored clean SEGs,
#    rebuilds only the 1 dirty function, and checks ONLY that function.
$CBC --hide-progress-bar -nworkers=16 -enable-incremental-persist \
     -persist-dir=./persist $CHK \
     --report=pr-report.json pr-injected-npd.bc
```

## Expected output

The incremental run detects exactly the one changed function and checks it:

```text
[Incremental persist] body-dirty: 1, +callers: 0, total dirty: 1
[SPEG] Start ... 1 functions to run (incremental; clean/loaded skipped)
```

… and the checker **finds the bug**:

```text
pr-report.json -> TotalBugs: 2   (both NULL Pointer Dereference, in the injected fn)
```

| | |
|--|--|
| Dirty functions detected | **1** (precisely the injected one) |
| SPEG functions analyzed | **1** (clean functions loaded from store, not rechecked) |
| **Bugs found** | **2 NPD**, both in `darknet_injected_npd_test` |
| Wall time (after store) | ~4 min (NPD checker) vs full-module scratch much longer |

So the feature both **speeds up** re-analysis (only 1 function re-SPEG'd) and
**still reports** the findings introduced by the PR.

## Key behavior: incremental reports ONLY changed-code findings

This is the most important thing to understand about bug-finding in incremental
mode:

> **Incremental runs checkers only on the functions that changed** (the dirty
> set). It does **not** reproduce a full-module bug report.

Consequences:

- A finding in unchanged code will **not** be reported by an incremental run,
  even though scratch (whole-module) would report it. The stored clean SEGs are
  not re-checked.
- This is the right behavior for **PR review**: "report what *this* change
  introduces", not "report every pre-existing bug in the codebase".
- To get the full (whole-module) report on a bitcode, run `cb-check` **without**
  `-enable-incremental-persist` (scratch mode).

### Worked numbers from this demo

On darknet, a full-module NPD scratch run is slow (timed out in our test at
>6 min). The incremental run finished in ~4 min and found exactly the 2 NPDs
in the one changed function. That is the feature working as intended:
**fast and focused on the diff**.

## Reproducing the `pr-injected-npd.bc` from source

The committed `.bc` is self-contained, but if you want to rebuild it:

```bash
cd <path>/darknet                # upstream: https://github.com/pjreddie/darknet
git checkout f6afaabc
# prepend this line to src/image.c:
printf '\nint darknet_injected_npd_test(int x) { int *p=(int*)0; if(x>0)p=(int*)0; return *p; }\n' | cat - src/image.c > /tmp/x && mv /tmp/x src/image.c
make clean
make -j$(nproc) CC=gclang CPP=gclang++ DEBUG=1 GPU=0 \
  CFLAGS='-Wall -Wno-unused-result -Wno-unknown-pragmas -Wfatal-errors -fPIC -O0 -g -Xclang -no-opaque-pointers'
get-bc -o pr-injected-npd.bc darknet
```

Requires gllvm + LLVM 15 typed pointers — see [`docs/producing-bitcode.md`](../docs/producing-bitcode.md).

## See also

- [`docs/cb-check-incremental-persist.md`](../docs/cb-check-incremental-persist.md) — "Bug-finding behavior" section
- [`bc/darknet/README.md`](../bc/darknet/README.md) — the real darknet PR bitcode (this demo is a synthetic addition to that tree)
