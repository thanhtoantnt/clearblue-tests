# Bug regression suite (`old.bc`)

Gate for **real bugs** on committed baselines `bc/<proj>/old.bc`.

If a future `fermat-check` **misses** any expected sink, the run **fails**
(exit 1). Extra findings are OK (warnings only).

Modeled after `FermatAnalyzerRegressionTest`, but expectations are curated
**true positives**, not the full analyzer dump.

## Current suite

| project | checker | expected TPs |
|---------|---------|--------------|
| libyaml | `-ps-npd` | **3** |
| fn_cares_qcache | `-ps-ml` + `-load-memory-spec` | **1** |

> **2026-08-20:** libyaml currently FAILS on FermatAnalyzer `main` @
> `82a6f5a5` (`-ps-npd` reports 0; baseline was recorded @ `e96525c3`).
> Upstream NPD regression, not this harness. fn_cares_qcache PASSES on the
> same binary.

### libyaml (yaml-0.2.5) — 3 NPD

Missing NULL check after `PEEK_TOKEN` when `first == 1` in `parser.c`:

| file:line | function |
|-----------|----------|
| `parser.c:733` | `yaml_parser_parse_block_sequence_entry` |
| `parser.c:841` | `yaml_parser_parse_block_mapping_key` |
| `parser.c:956` | `yaml_parser_parse_flow_sequence_entry` |

```c
token = PEEK_TOKEN(parser);   /* may be NULL */
/* uses token->start_mark without if (!token) */
```

UAF/IUSA noise from full dumps was triaged as FP and is **not** in the baseline.

## Known FNs → executable gates

| case | checker | bug | without spec | with spec |
|------|---------|-----|--------------|-----------|
| [`fn_cares_qcache/`](fn_cares_qcache/) | `-ps-ml` | c-ares `299bd617` qcache entry leak, pre-fix bitcode `d4bd20cc` | **ML = 0** (FN) | **found** (`ares_qcache_insert_int:374`) |

The case needs the pre-fix `buggy.bc` (rebuild from c-ares `d4bd20cc` with the
standard gllvm recipe, see the case README) and the committed `mem-spec.json`
(c-ares
alloc wrappers for `-load-memory-spec`). The harness passes `extra_args`
from `expected.json`, so this is a normal must-pass case — a future
`fermat-check` that regresses on spec-file alloc handling fails the gate.

## Run

```bash
cd ~/clearblue/incremental-persist-bench
export CBC=$HOME/github/FermatAnalyzer/build/tools/fermat-check/fermat-check

python3 scripts/run_bug_regression.py
# or one case:
python3 scripts/run_bug_regression.py --only libyaml
```

Flags used per case come from `expected.json` (`checkers`; currently `-ps-npd`
only, plus `-omit-no-dbginfo -nworkers=8 -report=...`).

Outputs: `results/bug_regression/<timestamp>/` (`report.json`, `compare.json`,
`summary.json`).

## Layout

```
bug_regression/
├── README.md
├── suite.json
└── libyaml/
    ├── expected.json   # must-find sinks
    └── test_config     # human summary
```

## Adding more TPs

1. Run `fermat-check -ps-npd ... bc/<proj>/old.bc`
2. Confirm each sink in source (not FP)
3. Add/update `bug_regression/<proj>/expected.json` with `checkers: "-ps-npd"`
   and the TP sink list only
4. Re-run the harness; it must PASS
