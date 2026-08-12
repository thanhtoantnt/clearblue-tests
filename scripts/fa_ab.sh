#!/usr/bin/env bash
# Full-analysis A/B: main vs feat on the PSA incremental-skip feature.
#
# Workflow per project:
#   1. STORE old.bc ONCE with feat (writes seg/ + psa/ + fingerprints)
#   2. Snapshot the pristine store dir
#   3. For each PR:
#      a. main incremental: reuse SEG, RECHECK ALL PSA (baseline)
#      b. feat incremental: reuse SEG, SKIP clean PSA (feature)
#
# The win: feat skips rechecking unchanged functions.
set -u
export GIT_TEMPLATE_DIR="${GIT_TEMPLATE_DIR:-$HOME/clearblue/local-tests/git/templates}"

MAIN="${MAIN:-/tmp/fermat-check-main}"
PERF="${PERF:-/tmp/fermat-check-feat}"
BC="${BC:-$HOME/clearblue/incremental-persist-bench/bc}"
OUT="${OUT:-/tmp/fa_ab.tsv}"
NWORKERS="${NWORKERS:-16}"
PRJS="${PRJS:-nghttp2}"
PR_TIMEOUT="${PR_TIMEOUT:-600}"
STORE_DIR="${STORE_DIR:-}"   # if set, skip store (reuse existing)

COMMON=(-omit-no-dbginfo -segbuilder-aa=falconplus -ps-npd -ps-uaf
        -psa-enable-side-effect-source --hide-progress-bar -nworkers=$NWORKERS)

[ -f "$OUT" ] || printf 'branch\tproject\tmode\tsample\tms\n' > "$OUT"

run_full() {  # bin pdir bcfile  -> echoes ms, sets rc
  local bin=$1 pdir=$2 bc=$3
  rm -rf "$pdir.tmp"; cp -r "$pdir" "$pdir.tmp"
  local t0 t1 rc
  t0=$(date +%s%N)
  timeout "$PR_TIMEOUT" "$bin" "${COMMON[@]}" \
    -enable-incremental-persist -persist-dir="$pdir.tmp" "$bc" >/dev/null 2>&1; rc=$?
  t1=$(date +%s%N)
  rm -rf "$pdir.tmp"
  echo $(( (t1-t0)/1000000 ))
  RC=$rc
}

for proj in $PRJS; do
  echo "===== $proj ====="
  pdir="/tmp/fa_${proj}"
  snap="/tmp/fa_${proj}_snap"

  # 1. Store (reuse if STORE_DIR given)
  if [ -n "$STORE_DIR" ] && [ -d "$STORE_DIR/seg" ]; then
    rm -rf "$pdir"; cp -r "$STORE_DIR" "$pdir"
    echo "[$proj] reused store from $STORE_DIR"
  else
    echo "[$proj] storing old.bc (feat)..."
    rm -rf "$pdir" "$snap"; mkdir -p "$pdir"
    t0=$(date +%s%N)
    timeout 2400 "$PERF" "${COMMON[@]}" -enable-incremental-persist \
      -persist-dir="$pdir" "$BC/$proj/old.bc" >/dev/null 2>&1; rc=$?
    t1=$(date +%s%N)
    [ $rc -ne 0 ] && { echo "[$proj] store FAIL rc=$rc (psa=$(ls "$pdir/psa/" 2>/dev/null|wc -l))"; continue; }
    echo "[$proj] store: $(( (t1-t0)/1000000 ))ms psa=$(ls "$pdir/psa/" 2>/dev/null|wc -l)"
  fi
  cp -r "$pdir" "$snap"

  # 2. Per-PR: main (recheck all) vs feat (skip clean)
  for bc in "$BC/$proj"/pr-*.bc; do
    [ -f "$bc" ] || continue
    s=$(basename "$bc" .bc)

    m=$(run_full "$MAIN" "$snap" "$bc")
    [ "$RC" -ne 0 ] && { echo "[$proj/$s] main FAIL rc=$RC"; } || \
      { printf 'main\t%s\tinc\t%s\t%s\n' "$proj" "$s" "$m" >> "$OUT"; echo "[$proj/$s] main: ${m}ms"; }

    f=$(run_full "$PERF" "$snap" "$bc")
    [ "$RC" -ne 0 ] && { echo "[$proj/$s] feat FAIL rc=$RC"; } || \
      { printf 'perf\t%s\tinc\t%s\t%s\n' "$proj" "$s" "$f" >> "$OUT"; echo "[$proj/$s] feat: ${f}ms"; }
  done
  rm -rf "$pdir" "$snap"
done
echo "done -> $OUT"
