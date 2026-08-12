#!/usr/bin/env bash
# Reproduce fermat-check incremental-persist numbers from committed bitcode.
#
# For each project under bc/<proj>/:
#   1. store  old.bc   -> fresh persist dir   (-enable-build-seg-only -persist-dir)
#   2. for every other *.bc (new.bc, pr-NNNN.bc, ...) run:
#        incremental  (-enable-incremental-persist -persist-dir)
#        scratch      (no persist)
#   3. append a row to results/<proj>/summary.tsv
#
# The committed bc/ only ships old.bc + new.bc per project (one PR sample each),
# so this reproduces ONE data point per project. To reproduce the full per-PR
# tables in results/, rebuild a pr-NNNN.bc per PR from source (see README.md
# "Reproducing the full per-PR tables") and drop them into bc/<proj>/.
set -u

# repo root = parent of this script's dir
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

CBC="${CBC:-$HOME/github/FermatAnalyzer/build/tools/fermat-check/fermat-check}"
NWORKERS="${NWORKERS:-16}"
PERSIST_ROOT="${PERSIST_ROOT:-$REPO/persist}"   # regeneratable; gitignored
RESULTS_ROOT="${RESULTS_ROOT:-$REPO/results}"
ONLY="${ONLY:-}"                                  # comma-sep project filter; empty = all
TIMEOUT="${TIMEOUT:-1800}"

log()  { echo "[$(date +%H:%M:%S)] $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

[ -x "$CBC" ] || die "fermat-check not found/executable at: $CBC (set CBC=...)"
command -v script >/dev/null || die "coreutils 'script' required for TTY capture"

# wrap fermat-check so its progress/diagnostics flush to the log file
run_cb() {
  local logfile=$1; shift
  script -q -c "timeout $TIMEOUT $CBC --hide-progress-bar -nworkers=$NWORKERS $*" "$logfile" >/dev/null 2>&1
  return $?
}

# parse: body_dirty callers total_dirty inc_seg_time
parse_inc() {
  tr '\r' '\n' < "$1" | python3 -c '
import sys, re
t = sys.stdin.read()
g = lambda p: (re.search(p, t) or [None, "?"])[1]
sg = re.search(r"SEG-Building spends time \*\*\*(.*?)\*\*\*", t)
print(g(r"body-dirty: (\d+)"),
      g(r"\+callers: (\d+)"),
      g(r"total dirty: (\d+)"),
      (sg.group(1).strip() if sg else "?"))
'
}
parse_seg() {
  tr '\r' '\n' < "$1" | python3 -c '
import sys, re
t = sys.stdin.read()
m = re.search(r"SEG-Building spends time \*\*\*(.*?)\*\*\*", t)
print(m.group(1).strip() if m else "?")
'
}

want() {                                # is project $1 in the ONLY filter?
  [ -z "$ONLY" ] && return 0
  case ",$ONLY," in *",$1,"*) return 0;; *) return 1;; esac
}

mkdir -p "$PERSIST_ROOT" "$RESULTS_ROOT"
log "fermat-check: $CBC"
log "repo:     $REPO"

for projdir in "$REPO"/bc/*/; do
  proj=$(basename "$projdir")
  want "$proj" || continue
  oldbc="$projdir/old.bc"
  [ -f "$oldbc" ] || { log "skip $proj: no old.bc"; continue; }

  pdir="$PERSIST_ROOT/$proj"
  rdir="$RESULTS_ROOT/$proj"
  mkdir -p "$rdir"
  rm -rf "$pdir"; mkdir -p "$pdir"
  summary="$rdir/summary.tsv"
  echo -e "sample\tstore_s\tinc_s\tscratch_s\tbody_dirty\tcallers\ttotal_dirty\tinc_seg\tscr_seg\tstatus" > "$summary"

  log "==== $proj : store old.bc ===="
  t0=$(date +%s)
  run_cb "$rdir/store.log" -enable-build-seg-only -persist-dir="$pdir" "$oldbc"
  rc=$?
  store_s=$(($(date +%s) - t0))
  [ $rc -ne 0 ] && { log "store failed ($rc) for $proj; skipping samples"; \
                     echo -e "old\t$store_s\t-\t-\t-\t-\t-\t-\t-\tstore_fail" >> "$summary"; continue; }
  log "store ok in ${store_s}s"

  # every *.bc except old.bc is a sample to bench
  for samplebc in "$projdir"/*.bc; do
    sname=$(basename "$samplebc" .bc)
    [ "$sname" = "old" ] && continue
    log "---- $proj / $sname ----"

    t0=$(date +%s)
    run_cb "$rdir/inc_$sname.log" -enable-build-seg-only -enable-incremental-persist -persist-dir="$pdir" "$samplebc"
    inc_rc=$?
    inc_s=$(($(date +%s) - t0))

    t0=$(date +%s)
    run_cb "$rdir/scr_$sname.log" -enable-build-seg-only "$samplebc"
    scr_rc=$?
    scr_s=$(($(date +%s) - t0))

    read -r bd ca td iseg <<<"$(parse_inc "$rdir/inc_$sname.log")"
    sseg="$(parse_seg "$rdir/scr_$sname.log")"
    status=$([ $inc_rc -eq 0 ] && [ $scr_rc -eq 0 ] && echo ok || echo err)
    log "$proj/$sname inc=${inc_s}s scr=${scr_s}s dirty=${bd}+${ca}=${td} ($status)"
    echo -e "$sname\t$store_s\t$inc_s\t$scr_s\t$bd\t$ca\t$td\t$iseg\t$sseg\t$status" >> "$summary"
  done
done

log "done. summaries:"
for s in "$RESULTS_ROOT"/*/summary.tsv; do
  [ -f "$s" ] && { echo "--- $s ---"; column -t -s$'\t' "$s" 2>/dev/null || cat "$s"; }
done
