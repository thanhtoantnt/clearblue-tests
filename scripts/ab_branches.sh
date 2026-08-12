#!/usr/bin/env bash
# A/B compare two fermat-check builds on the incremental-persist feature.
#
# Real workflow per branch:
#   1. store old.bc ONCE  (setup)
#   2. incremental on EACH pr-*.bc (reuse the store)
# Compare two branches (e.g. main vs perf) on those numbers.
#
# See docs/ab-branch-comparison.md for the methodology.
#
# Usage:
#   MAIN=/tmp/fermat-check-main PERF=/tmp/fermat-check-perf ./scripts/ab_branches.sh
#   PROJECTS="darknet openssl" ./scripts/ab_branches.sh   # subset
#   OUT=/tmp/ab.tsv ./scripts/ab_branches.sh              # custom output
set -u
export GIT_TEMPLATE_DIR="${GIT_TEMPLATE_DIR:-$HOME/clearblue/local-tests/git/templates}"

MAIN="${MAIN:-/tmp/fermat-check-main}"
PERF="${PERF:-/tmp/fermat-check-perf}"
BC="${BC:-$HOME/clearblue/incremental-persist-bench/bc}"
OUT="${OUT:-/tmp/ab2.tsv}"
NWORKERS="${NWORKERS:-16}"
RUNS="${RUNS:-1}"   # repeats for min-of-N; 1 is enough for branch comparisons

[ -f "$OUT" ] || printf 'branch\tproject\tmode\tsample\tms\n' > "$OUT"
have() { awk -F'\t' -v b="$1" -v p="$2" -v m="$3" -v s="$4" 'NR>1 && $1==b && $2==p && $3==m && $4==s{print "y"; exit}' "$OUT"; }

run_branch_project() {  # binary branch project
  local bin=$1 branch=$2 proj=$3
  local pdir="/tmp/ab_${branch}_${proj}"
  local store_snap="/tmp/ab_${branch}_${proj}_snap"   # pristine store snapshot
  local args=(--hide-progress-bar -nworkers=$NWORKERS -enable-build-seg-only)

  # 1. store old.bc once
  if [ -z "$(have "$branch" "$proj" store old)" ]; then
    rm -rf "$pdir" "$store_snap"; mkdir -p "$pdir"
    local t0 t1 rc
    t0=$(date +%s%N)
    timeout 600 "$bin" "${args[@]}" -serialize-seg -store-models-dir="$pdir" "$BC/$proj/old.bc" >/dev/null 2>&1; rc=$?
    t1=$(date +%s%N)
    [ $rc -ne 0 ] && { echo "[$branch/$proj] store FAIL"; return; }
    printf '%s\t%s\tstore\told\t%s\n' "$branch" "$proj" "$(( (t1-t0)/1000000 ))" >> "$OUT"
    echo "[$branch/$proj] store: $(( (t1-t0)/1000000 ))ms"
    # Snapshot the pristine store so each incremental run starts clean.
    # Incremental mode writes rebuilt SEGs back to the dir; without a fresh
    # copy each PR contaminates the next (rc=2 on large projects).
    cp -r "$pdir" "$store_snap"
  fi

  # 2. incremental on each pr-*.bc (reuse the stored SEGs)
  for bc in "$BC/$proj"/pr-*.bc; do
    [ -f "$bc" ] || continue
    local s=$(basename "$bc" .bc)
    local r
    for r in $(seq 1 "$RUNS"); do
      [ -n "$(have "$branch" "$proj" inc "$s")" ] && continue   # resumable
      # Restore pristine store before each PR so prior runs don't contaminate.
      rm -rf "$pdir"; cp -r "$store_snap" "$pdir"
      local t0 t1 rc
      t0=$(date +%s%N)
      timeout 600 "$bin" "${args[@]}" -enable-incremental-persist -store-models-dir="$pdir" "$bc" >/dev/null 2>&1; rc=$?
      t1=$(date +%s%N)
      if [ $rc -ne 0 ]; then
        echo "[$branch/$proj/$s] inc FAIL (rc=$rc)"
      else
        printf '%s\t%s\tinc\t%s\t%s\n' "$branch" "$proj" "$s" "$(( (t1-t0)/1000000 ))" >> "$OUT"
        echo "[$branch/$proj/$s] inc: $(( (t1-t0)/1000000 ))ms"
      fi
    done
  done
  rm -rf "$pdir" "$store_snap"
}

PROJECTS="${PROJECTS:-c-ares libuv libssh2 mbedtls nghttp2 memcached libevent curl libjpeg-turbo wolfssl openssh darknet zstd redis openssl git}"

for proj in $PROJECTS; do
  [ -d "$BC/$proj" ] || { echo "skip $proj"; continue; }
  echo "===== $proj ====="
  run_branch_project "$MAIN" main "$proj"
  run_branch_project "$PERF" perf "$proj"
done
echo "=== DONE: $OUT ==="
echo "Summarize:  python3 scripts/ab_summarize.py $OUT"
