#!/usr/bin/env bash
# Store old.bc, change one caller, and check that incremental matches scratch
# inside the dirty cone.
#
# A mismatch (a cone bug dropped, or a bug incremental invented) fails the run.
# A slower incremental run does not: a caller cone that holds the expensive
# functions can tie scratch and still be correct.
#
# *.bc is gitignored, so the changed bitcode is generated into results/ from
# the store report. Any other bc/<proj>/*.bc (except old.bc) is still timed.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

CBC="${CBC:-$HOME/github/FermatAnalyzer/build/tools/fermat-check/fermat-check}"
NWORKERS="${NWORKERS:-8}"
PERSIST_ROOT="${PERSIST_ROOT:-$REPO/persist}"
RESULTS_ROOT="${RESULTS_ROOT:-$REPO/results}"
ONLY="${ONLY:-}"
TIMEOUT="${TIMEOUT:-1800}"
# PSA summaries are what incremental loads. Without a checker, the cone
# comparison has nothing to agree on.
CHECKERS="${CHECKERS:---ps-npd}"
LLVM_DIS="${LLVM_DIS:-/usr/lib/llvm-15/bin/llvm-dis}"
LLVM_AS="${LLVM_AS:-/usr/lib/llvm-15/bin/llvm-as}"

log()  { echo "[$(date +%H:%M:%S)] $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

[ -x "$CBC" ] || die "fermat-check not found/executable at: $CBC (set CBC=...)"
[ -x "$LLVM_DIS" ] || die "llvm-dis not found at: $LLVM_DIS"
[ -x "$LLVM_AS" ] || die "llvm-as not found at: $LLVM_AS"
command -v script >/dev/null || die "coreutils 'script' required for TTY capture"

FAIL=0

run_cb() {
  local logfile=$1; shift
  # -e: propagate fermat-check's exit code. Without it a timeout looks like success.
  script -q -e -c "timeout $TIMEOUT $CBC --hide-progress-bar -nworkers=$NWORKERS $*" "$logfile" >/dev/null 2>&1
  return $?
}

parse_inc() {
  tr '\r' '\n' < "$1" | python3 -c '
import sys, re
t = sys.stdin.read()
def g(p, d="?"):
    m = re.search(p, t)
    return m.group(1) if m else d
print(g(r"body-dirty: (\d+)"),
      g(r"scheduler work set: (\d+)"),
      g(r"PSA summaries loaded: (\d+)"),
      g(r"recheck failed-load: (\d+)", "0"))
'
}

want() {
  [ -z "$ONLY" ] && return 0
  case ",$ONLY," in *",$1,"*) return 0;; *) return 1;; esac
}

# bench_one <proj> <sample.bc> <sample-name> <store_s> <summary> <rdir> <pdir> <mutated-or-dash>
bench_one() {
  local proj=$1 samplebc=$2 sname=$3 store_s=$4 summary=$5 rdir=$6 pdir=$7 mutated=$8
  log "---- $proj / $sname ----"
  local t0 inc_rc inc_s scr_rc scr_s
  t0=$(date +%s)
  run_cb "$rdir/inc_$sname.log" \
    -enable-incremental-persist -store-models-dir="$pdir" -store-module-name="$proj" \
    $CHECKERS --report="$rdir/inc_$sname.json" "$samplebc"
  inc_rc=$?
  inc_s=$(($(date +%s) - t0))

  t0=$(date +%s)
  run_cb "$rdir/scr_$sname.log" $CHECKERS --report="$rdir/scr_$sname.json" "$samplebc"
  scr_rc=$?
  scr_s=$(($(date +%s) - t0))

  local bd ws loaded recheck
  read -r bd ws loaded recheck <<<"$(parse_inc "$rdir/inc_$sname.log")"
  local workset="$pdir/$proj/workset_funcs.$sname.txt"
  local invented=0 missing=0 cmp=skip status=err
  if [ "$inc_rc" -ne 0 ] || [ "$scr_rc" -ne 0 ]; then
    status=err
    FAIL=1
  elif [ ! -f "$workset" ]; then
    status=no_workset
    FAIL=1
  else
    cmp=$(python3 "$SCRIPT_DIR/compare_cone_reports.py" \
      "$rdir/inc_$sname.json" "$rdir/scr_$sname.json" "$workset")
    local cmp_rc=$?
    invented=$(echo "$cmp" | head -1 | awk '{print $4}' | cut -d= -f2)
    missing=$(echo "$cmp" | head -1 | awk '{print $5}' | cut -d= -f2)
    echo "$cmp"
    if [ "$cmp_rc" -ne 0 ]; then
      status=report_mismatch
      FAIL=1
    elif [ "$loaded" = "0" ] || [ "${recheck:-0}" != "0" ]; then
      # The bug matched, but the clean callee was not loaded. That is the
      # hole this bench exists to catch.
      status=load_fail
      FAIL=1
    else
      status=ok
    fi
  fi
  log "$proj/$sname inc=${inc_s}s scr=${scr_s}s dirty=$bd workset=$ws loaded=$loaded recheck=$recheck ($status)"
  echo -e "$sname\t$store_s\t$inc_s\t$scr_s\t$bd\t$ws\t$loaded\t$recheck\t${invented:-?}\t${missing:-?}\t$mutated\t$status" >> "$summary"
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
  echo -e "sample\tstore_s\tinc_s\tscratch_s\tbody_dirty\tworkset\tloaded\trecheck\tinvented\tmissing\tmutated\tstatus" > "$summary"

  log "==== $proj : store old.bc ===="
  t0=$(date +%s)
  run_cb "$rdir/store.log" \
    -store-seg -store-models-dir="$pdir" -store-module-name="$proj" \
    $CHECKERS --report="$rdir/store.json" "$oldbc"
  rc=$?
  store_s=$(($(date +%s) - t0))
  if [ $rc -ne 0 ]; then
    log "store failed ($rc) for $proj"
    echo -e "old\t$store_s\t-\t-\t-\t-\t-\t-\t-\t-\t-\tstore_fail" >> "$summary"
    FAIL=1
    continue
  fi
  log "store ok in ${store_s}s"

  caller_bc="$rdir/caller.bc"
  if mutated=$(python3 "$SCRIPT_DIR/make_caller_bc.py" \
      "$rdir/store.json" "$oldbc" "$caller_bc" "$LLVM_DIS" "$LLVM_AS"); then
    log "$proj caller change: $mutated"
    bench_one "$proj" "$caller_bc" caller "$store_s" "$summary" "$rdir" "$pdir" "$mutated"
  else
    log "$proj: no multi-function bug; cone check skipped"
    echo -e "caller\t$store_s\t-\t-\t-\t-\t-\t-\t-\t-\t-\tno_cone_bug" >> "$summary"
  fi

  for samplebc in "$projdir"/*.bc; do
    sname=$(basename "$samplebc" .bc)
    [ "$sname" = "old" ] && continue
    bench_one "$proj" "$samplebc" "$sname" "$store_s" "$summary" "$rdir" "$pdir" "-"
  done
  rm -rf "$pdir"
done

log "done. summaries:"
for s in "$RESULTS_ROOT"/*/summary.tsv; do
  [ -f "$s" ] && { echo "--- $s ---"; column -t -s$'\t' "$s" 2>/dev/null || cat "$s"; }
done
exit "$FAIL"
