#!/usr/bin/env bash
# Regenerate per-PR bitcode for a project → bc/<proj>/pr-<NNNN>.bc
#
# Reads the PR list from results/<proj>/summary.tsv (or results/round2/summary.tsv
# for libuv/darknet/redis/openssl). For each PR: reset the upstream source tree
# to the baseline commit, apply the PR's .c/.h files, rebuild with the SAME
# gllvm flags that produced old.bc, and save bitcode as bc/<proj>/pr-<NNNN>.bc.
#
# Synthetic entries (syn0, syn1, ...) are reproduced by inserting a no-op
# comment into a source file (see synthetic_touch).
#
# Resumable: skips a PR whose pr-<NNNN>.bc already exists.
#
# Usage:
#   ./scripts/build_pr_bc.sh <project>        # one project
#   ./scripts/build_pr_bc.sh all              # every project
#   PRS="22328 22326" ./scripts/build_pr_bc.sh curl   # override PR list
set -u

export PATH="$HOME/go/bin:$HOME/tools/llvm15-official/bin:$PATH"
export LLVM_COMPILER_PATH="$HOME/tools/llvm15-official/bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_ROOT="${SRC_ROOT:-$HOME/clearblue/local-tests}"
GFLAGS='-O0 -g -fPIC -Xclang -no-opaque-pointers'

log()  { echo "[$(date +%H:%M:%S)] $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

command -v gclang >/dev/null || die "gclang not on PATH (install gllvm, set PATH/LLVM_COMPILER_PATH)"
command -v get-bc >/dev/null || die "get-bc not on PATH"

# ---- per-project config ----------------------------------------------------
cfg() {  # cfg <project> -> echoes: srcdir|ghrepo|artifact|builder
  case "$1" in
    curl)    echo "$SRC_ROOT/curl|curl/curl|build-gllvm/lib/libcurl-d.so.4.8.0|curl" ;;
    git)     echo "$SRC_ROOT/git|git/git|git|git" ;;
    libuv)   echo "$SRC_ROOT/libuv|libuv/libuv|@cmake|libuv" ;;
    darknet) echo "$SRC_ROOT/darknet|pjreddie/darknet|darknet|darknet" ;;
    redis)   echo "$SRC_ROOT/redis|redis/redis|src/redis-server|redis" ;;
    openssl) echo "$SRC_ROOT/openssl|openssl/openssl|libcrypto.so.3|openssl" ;;
    *) die "unknown project: $1" ;;
  esac
}

# ---- builders (port of bench_incremental_all.sh) ---------------------------
build_curl() {  # $1=srcdir $2=artifact
  ( cd "$1"
    rm -rf build-prbc && mkdir build-prbc && cd build-prbc
    cmake .. -G Ninja -DCMAKE_C_COMPILER=gclang \
      -DCMAKE_C_FLAGS="$GFLAGS" -DCMAKE_BUILD_TYPE=Debug \
      -DBUILD_SHARED_LIBS=ON -DCURL_USE_OPENSSL=OFF \
      -DCURL_DISABLE_LDAP=ON -DCURL_USE_LIBPSL=OFF >/tmp/prbc_curl_cm.log 2>&1 || return 1
    ninja -j"$(nproc)" >/tmp/prbc_curl_nj.log 2>&1 || return 1
    get-bc -o /tmp/prbc_out.bc "$(find . -name 'libcurl-d.so*' -type f | head -1)" >/dev/null 2>&1 || return 1
  )
}
build_git() {  # $1=srcdir
  ( cd "$1"
    make -j"$(nproc)" CC=gclang CFLAGS="$GFLAGS" \
      NO_OPENSSL=1 NO_CURL=1 NO_EXPAT=1 NO_GETTEXT=1 git >/tmp/prbc_git.log 2>&1 || return 1
    get-bc -o /tmp/prbc_out.bc git >/dev/null 2>&1 || return 1
  )
}
build_libuv() {  # $1=srcdir
  local bdir; bdir=$(mktemp -d /tmp/prbc_libuv.XXXXXX)
  cmake -S "$1" -B "$bdir" -G Ninja -DCMAKE_C_COMPILER=gclang \
    -DCMAKE_C_FLAGS="$GFLAGS" -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=OFF >/tmp/prbc_libuv_cm.log 2>&1 || return 1
  ninja -C "$bdir" -j"$(nproc)" >/tmp/prbc_libuv_nj.log 2>&1 || return 1
  get-bc -o /tmp/prbc_out.bc "$bdir"/libuv.so.1.0.0 >/dev/null 2>&1 || \
    get-bc -o /tmp/prbc_out.bc "$bdir"/libuv.so >/dev/null 2>&1 || return 1
  rm -rf "$bdir"
}
build_darknet() {  # $1=srcdir
  ( cd "$1"
    make clean >/dev/null 2>&1
    make -j"$(nproc)" CC=gclang CPP=gclang++ DEBUG=1 GPU=0 \
      CFLAGS="-Wall -Wno-unused-result -Wno-unknown-pragmas -Wfatal-errors -fPIC $GFLAGS" \
      >/tmp/prbc_dn.log 2>&1 || return 1
    get-bc -o /tmp/prbc_out.bc darknet >/dev/null 2>&1 || return 1
  )
}
build_redis() {  # $1=srcdir
  ( cd "$1"
    # ponytail: upstream declares the cb with a ctor-init that gclang/LLVM15 dislikes; drop the =NULL
    sed -i 's/static redisAtomic run_on_thread_cb g_callback = NULL;/static redisAtomic run_on_thread_cb g_callback;/' src/threads_mngr.c 2>/dev/null || true
    make -j"$(nproc)" CC=gclang OPTIMIZATION="-O0" \
      CFLAGS="$GFLAGS -fno-lto -Wno-error -std=gnu11" LDFLAGS="-fno-lto" \
      MALLOC=libc BUILD_TLS=no >/tmp/prbc_rd.log 2>&1 || return 1
    get-bc -o /tmp/prbc_out.bc src/redis-server >/dev/null 2>&1 || return 1
  )
}
build_openssl() {  # $1=srcdir
  ( cd "$1"
    [ -f Makefile ] || ./config CC=gclang CFLAGS="$GFLAGS" no-asm shared -d >/tmp/prbc_os.log 2>&1 || return 1
    # build_libs only — skip fuzz/test/apps targets that can break on PR edits
    make -j"$(nproc)" build_libs >/tmp/prbc_os_mk.log 2>&1 || {
      ./config CC=gclang CFLAGS="$GFLAGS" no-asm shared -d >/tmp/prbc_os.log 2>&1 || return 1
      make -j"$(nproc)" build_libs >/tmp/prbc_os_mk.log 2>&1 || return 1; }
    local a; a=$(find . -name 'libcrypto.so*' -type f | head -1)
    get-bc -o /tmp/prbc_out.bc "${a:-libcrypto.so.3}" >/dev/null 2>&1 || return 1
  )
}

# ---- PR apply --------------------------------------------------------------
# No GitHub API needed: fetch the PR ref over SSH, then read its changed
# .c/.h/.cc/.cpp files from git (diff merge-base..PR-head) and copy them in.
apply_pr_files() {  # $1=srcdir $2=ghrepo $3=pr
  local srcdir=$1 repo=$2 pr=$3 ref=prbc-$pr
  ( cd "$srcdir"
    git fetch origin "pull/$pr/head:$ref" >/tmp/prbc_fetch.log 2>&1 || return 1
    local mb files ok=0 f
    mb=$(git merge-base HEAD "$ref" 2>/dev/null)
    files=$(git diff --name-only "${mb:-HEAD}" "$ref" 2>/dev/null | rg '\.(c|h|cc|cpp)$' || true)
    [ -n "$files" ] || { git branch -D "$ref" >/dev/null 2>&1; return 1; }
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      if git show "$ref:$f" >/tmp/prbc_pf 2>/dev/null; then
        mkdir -p "$(dirname "$f")"; cp /tmp/prbc_pf "$f" && ok=1
      fi
    done <<< "$files"
    git branch -D "$ref" >/dev/null 2>&1 || true
    [ "$ok" -eq 1 ]
  )
}

synthetic_touch() {  # $1=srcdir $2=index  -> reproduces a syn<N> edit
  ( cd "$1"
    python3 - "$2" <<'PY'
import sys, pathlib, re
idx=int(sys.argv[1])
cands=sorted(p for p in pathlib.Path('.').rglob('*.c')
             if not any(x in str(p) for x in ['test','doc','example','3rdparty','deps','vendor']))
if not cands: sys.exit(1)
p=cands[idx % len(cands)]; t=p.read_text(errors='ignore')
m=re.search(r'\n\{', t) or re.search(r'\{\n', t)
if not m: sys.exit(2)
mark=f'  /* incremental-bench-touch-{idx} */\n'
if mark.strip() in t: mark=f'  /* incremental-bench-touch-{idx}-b */\n'
p.write_text(t[:m.end()]+mark+t[m.end():])
PY
  )
}

# ---- main ------------------------------------------------------------------
read_prs() {  # $1=project -> echo PR list (from committed results); skip non-PR rows
  local proj=$1 src
  for src in "$REPO/results/$proj/summary.tsv" "$REPO/results/round2/summary.tsv"; do
    [ -f "$src" ] || continue
    if [ "$src" = "$REPO/results/round2/summary.tsv" ]; then
      awk -F'\t' -v P="$proj" 'NR>1 && $1==P {print $2}' "$src"
    else
      awk -F'\t' 'NR>1 {print $1}' "$src"
    fi
  done | awk '/^[0-9]+$|^syn[0-9]+$/ {print}'   # keep only numeric PRs or syn<N>
}

do_project() {
  local proj=$1
  local cfg srcdir repo artifact builder
  cfg=$(cfg "$proj"); IFS='|' read -r srcdir repo artifact builder <<<"$cfg"
  [ -d "$srcdir/.git" ] || die "source not found: $srcdir"
  local bcdir="$REPO/bc/$proj"; mkdir -p "$bcdir"

  local base; base=$(git -C "$srcdir" rev-parse --short HEAD)
  log "==== $proj : src=$srcdir repo=$repo base=$base ===="

  # ensure old.bc present
  if [ ! -s "$bcdir/old.bc" ]; then
    log "$proj build old.bc"
    ( cd "$srcdir"; git checkout -- . >/dev/null 2>&1; git clean -fd >/dev/null 2>&1 || true )
    "build_$builder" "$srcdir" "$artifact" || die "$proj old.bc build failed"
    cp /tmp/prbc_out.bc "$bcdir/old.bc"
    log "$proj old.bc ready ($(du -h "$bcdir/old.bc" | cut -f1))"
  fi

  # PR list (override via PRS=)
  local prs=()
  if [ -n "${PRS:-}" ]; then read -ra prs <<<"$PRS"; else mapfile -t prs < <(read_prs "$proj"); fi
  log "$proj PRs: ${prs[*]}"

  local pr got=0 fail=0
  for pr in "${prs[@]}"; do
    local out="$bcdir/pr-$pr.bc"
    [ -s "$out" ] && { log "$proj pr-$pr.bc exists, skip"; got=$((got+1)); continue; }

    # preserve per-object .o.bc (gllvm sidecars) + build dirs so get-bc can still
    # link the whole artifact after make only rebuilds the changed PR file.
    # git clean -e needs separate patterns for hidden (.*.bc) vs normal (*.bc).
    ( cd "$srcdir"; git reset --hard "$base" >/dev/null 2>&1; git checkout -- . >/dev/null 2>&1
      git clean -fd -e '*.bc' -e '.*.bc' -e 'build-prbc' -e 'build-gllvm' >/dev/null 2>&1 || true )

    if [[ "$pr" == syn* ]]; then
      synthetic_touch "$srcdir" "${pr#syn}" || { log "$proj $pr touch fail"; fail=$((fail+1)); continue; }
    else
      apply_pr_files "$srcdir" "$repo" "$pr" || { log "$proj pr-$pr apply fail"; fail=$((fail+1)); continue; }
    fi

    if "build_$builder" "$srcdir" "$artifact"; then
      cp /tmp/prbc_out.bc "$out"
      log "$proj pr-$pr.bc ready ($(du -h "$out" | cut -f1))"; got=$((got+1))
    else
      log "$proj pr-$pr build fail"; fail=$((fail+1))
    fi
  done
  log "$proj done: ${got} ok, ${fail} fail, $(ls "$bcdir"/pr-*.bc 2>/dev/null | wc -l) pr-*.bc files"
}

[ $# -ge 1 ] || die "usage: $0 <project|all>   [env: PRS='...', SRC_ROOT=...]"
if [ "$1" = all ]; then
  for p in libuv curl darknet redis git openssl; do do_project "$p"; done
else
  do_project "$1"
fi
log "ALL DONE"
