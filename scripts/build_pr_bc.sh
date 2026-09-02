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
#   ONLY_OLD=1 ./scripts/build_pr_bc.sh curl  # rebuild bc/<proj>/old.bc only
set -u

export PATH="$HOME/go/bin:$HOME/tools/llvm15-official/bin:$PATH"
export LLVM_COMPILER_PATH="$HOME/tools/llvm15-official/bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_ROOT="${SRC_ROOT:-$REPO/src}"
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
    c-ares)  echo "$SRC_ROOT/c-ares|c-ares/c-ares|@cmake|cares" ;;
    libevent) echo "$SRC_ROOT/libevent|libevent/libevent|@cmake|libevent" ;;
    mbedtls) echo "$SRC_ROOT/mbedtls|Mbed-TLS/mbedtls|@cmake|mbedtls" ;;
    openssh) echo "$SRC_ROOT/openssh|openssh/openssh-portable|sshd|openssh" ;;
    nghttp2) echo "$SRC_ROOT/nghttp2|nghttp2/nghttp2|@cmake|nghttp2" ;;
    libssh2) echo "$SRC_ROOT/libssh2|libssh2/libssh2|@cmake|libssh2" ;;
    memcached) echo "$SRC_ROOT/memcached|memcached/memcached|memcached|memcached" ;;
    libjpeg-turbo) echo "$SRC_ROOT/libjpeg-turbo|libjpeg-turbo/libjpeg-turbo|libjpeg.so.62.4.0|libjpegturbo" ;;
    libexpat) echo "$SRC_ROOT/libexpat|libexpat/libexpat|expat|libexpat" ;;
    libsodium) echo "$SRC_ROOT/libsodium|jedisct1/libsodium|libsodium|libsodium" ;;
    libyaml) echo "$SRC_ROOT/libyaml|yaml/libyaml|libyaml|libyaml" ;;
    unbound) echo "$SRC_ROOT/unbound|NLnetLabs/unbound|unbound|unbound" ;;
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
    so=$(find . -name 'libcurl-d.so*' -type f ! -type l | head -1)
    get-bc -o /tmp/prbc_out.bc "$so" >/dev/null 2>&1 || \
      getbc-link "$so" -o /tmp/prbc_out.bc >/tmp/prbc_curl_gb.log 2>&1 || return 1
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
  so=$(find "$bdir" -name 'libuv.so*' -type f | head -1)
  get-bc -o /tmp/prbc_out.bc "$so" >/dev/null 2>&1 || \
    getbc-link "$so" -o /tmp/prbc_out.bc >/tmp/prbc_libuv_gb.log 2>&1 || return 1
  rm -rf "$bdir"
}
build_cares() {  # $1=srcdir
  ( cd "$1"
    rm -rf build-prbc && mkdir build-prbc && cd build-prbc
    cmake .. -G Ninja -DCMAKE_C_COMPILER=gclang \
      -DCMAKE_C_FLAGS="$GFLAGS" -DCMAKE_BUILD_TYPE=Debug \
      -DCARES_SHARED=ON -DCARES_STATIC=OFF >/tmp/prbc_cares_cm.log 2>&1 || return 1
    ninja -j"$(nproc)" >/tmp/prbc_cares_nj.log 2>&1 || return 1
    so=$(find . -name 'libcares.so*' -type f ! -type l | head -1)
    get-bc -o /tmp/prbc_out.bc "$so" >/dev/null 2>&1 || \
      getbc-link "$so" -o /tmp/prbc_out.bc >/tmp/prbc_cares_gb.log 2>&1 || return 1
  )
}
build_libevent() {  # $1=srcdir
  ( cd "$1"
    rm -rf build-prbc && mkdir build-prbc && cd build-prbc
    cmake .. -G Ninja -DCMAKE_C_COMPILER=gclang \
      -DCMAKE_C_FLAGS="$GFLAGS" -DCMAKE_BUILD_TYPE=Debug \
      -DEVENT__LIBRARY_TYPE=SHARED \
      -DEVENT__DISABLE_OPENSSL=ON -DEVENT__DISABLE_MBEDTLS=ON \
      -DEVENT__DISABLE_TESTS=ON -DEVENT__DISABLE_SAMPLES=ON >/tmp/prbc_lev_cm.log 2>&1 || return 1
    ninja -j"$(nproc)" >/tmp/prbc_lev_nj.log 2>&1 || return 1
    # core is the smallest meaningful target; soname version varies
    so=$(find . -name 'libevent_core*.so*' -type f | head -1)
    get-bc -o /tmp/prbc_out.bc "$so" >/dev/null 2>&1 || \
      getbc-link "$so" -o /tmp/prbc_out.bc >/tmp/prbc_lev_gb.log 2>&1 || return 1
  )
}
build_mbedtls() {  # $1=srcdir
  ( cd "$1"
    git submodule update --init --recursive >/tmp/prbc_mb_sub.log 2>&1 || true
    rm -rf build-prbc && mkdir build-prbc && cd build-prbc
    cmake .. -G Ninja -DCMAKE_C_COMPILER=gclang \
      -DCMAKE_C_FLAGS="$GFLAGS" -DCMAKE_BUILD_TYPE=Debug \
      -DENABLE_PROGRAMS=OFF -DENABLE_TESTING=OFF \
      -DUSE_SHARED_MBEDTLS_LIBRARY=ON >/tmp/prbc_mb_cm.log 2>&1 || return 1
    ninja -j"$(nproc)" >/tmp/prbc_mb_nj.log 2>&1 || return 1
    so=$(find . -name 'libmbedtls.so*' -type f | head -1)
    get-bc -o /tmp/prbc_out.bc "$so" >/dev/null 2>&1 || \
      getbc-link "$so" -o /tmp/prbc_out.bc >/tmp/prbc_mb_gb.log 2>&1 || return 1
  )
}
build_openssh() {  # $1=srcdir  $2=artifact (sshd)
  ( cd "$1"
    [ -f configure ] || autoreconf -fi >/tmp/prbc_ss_ar.log 2>&1 || return 1
    [ -f Makefile ] || ./configure CC=gclang CFLAGS="$GFLAGS" >/tmp/prbc_ss_cf.log 2>&1 || return 1
    make -j"$(nproc)" sshd >/tmp/prbc_ss_mk.log 2>&1 || return 1
    get-bc -o /tmp/prbc_out.bc sshd >/dev/null 2>&1 || \
      getbc-link sshd -o /tmp/prbc_out.bc >/tmp/prbc_ss_gb.log 2>&1 || return 1
  )
}
build_unbound() {  # $1=srcdir  $2=artifact (unbound daemon)
  ( cd "$1"
    [ -f Makefile ] || ./configure CC=gclang CFLAGS="$GFLAGS" \
      --disable-shared --enable-static \
      --without-pyunbound --without-pythonmodule \
      --disable-flto --disable-rpath \
      --with-libevent=no --with-libhiredis=no >/tmp/prbc_ub_cf.log 2>&1 || return 1
    make -j"$(nproc)" unbound >/tmp/prbc_ub_mk.log 2>&1 || return 1
    get-bc -o /tmp/prbc_out.bc unbound >/dev/null 2>&1 || \
      getbc-link unbound -o /tmp/prbc_out.bc >/tmp/prbc_ub_gb.log 2>&1 || return 1
  )
}
build_nghttp2() {  # $1=srcdir
  ( cd "$1"
    rm -rf build-prbc && mkdir build-prbc && cd build-prbc
    cmake .. -G Ninja -DCMAKE_C_COMPILER=gclang \
      -DCMAKE_C_FLAGS="$GFLAGS" -DCMAKE_BUILD_TYPE=Debug \
      -DENABLE_SHARED_LIB=ON -DBUILD_STATIC_LIBS=OFF \
      -DENABLE_APP=OFF -DENABLE_HPACK_TOOLS=OFF -DENABLE_EXAMPLES=OFF >/tmp/prbc_ng_cm.log 2>&1 || return 1
    ninja -j"$(nproc)" >/tmp/prbc_ng_nj.log 2>&1 || return 1
    so=$(find . -name 'libnghttp2.so*' -type f | head -1)
    get-bc -o /tmp/prbc_out.bc "$so" >/dev/null 2>&1 || \
      getbc-link "$so" -o /tmp/prbc_out.bc >/tmp/prbc_ng_gb.log 2>&1 || return 1
  )
}
build_libssh2() {  # $1=srcdir
  local bdir; bdir=$(mktemp -d /tmp/prbc_ssh2.XXXXXX)
  cmake -S "$1" -B "$bdir" -G Ninja -DCMAKE_C_COMPILER=gclang \
    -DCMAKE_C_FLAGS="$GFLAGS" -DCMAKE_BUILD_TYPE=Debug \
    -DBUILD_SHARED_LIBS=ON -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF \
    -DENABLE_ZLIB_COMPRESSION=OFF >/tmp/prbc_ssh2_cm.log 2>&1 || { rm -rf "$bdir"; return 1; }
  ninja -C "$bdir" -j"$(nproc)" >/tmp/prbc_ssh2_nj.log 2>&1 || { rm -rf "$bdir"; return 1; }
  so=$(find "$bdir" -name 'libssh2.so*' -type f | head -1)
  get-bc -o /tmp/prbc_out.bc "$so" >/dev/null 2>&1 || \
    getbc-link "$so" -o /tmp/prbc_out.bc >/tmp/prbc_ssh2_gb.log 2>&1 || { rm -rf "$bdir"; return 1; }
  rm -rf "$bdir"
}
# memcached needs libevent; ensure libevent is installed to this prefix first
# (cmake --install <libevent build dir> --prefix "$MC_LEV"), see producing-bitcode.md
MC_LEV="${MC_LEV:-/tmp/libevent-install}"
build_memcached() {  # $1=srcdir  $2=artifact (memcached)
  ( cd "$1"
    [ -f configure ] || { ./autogen.sh >/tmp/prbc_mc_ag.log 2>&1; autoreconf -fi >/tmp/prbc_mc_ar.log 2>&1; automake --add-missing --copy >/tmp/prbc_mc_am.log 2>&1; }
    [ -f Makefile ] || ./configure CC=gclang CFLAGS="$GFLAGS" --with-libevent="$MC_LEV" \
      LDFLAGS="-L$MC_LEV/lib -Wl,-rpath,$MC_LEV/lib" CPPFLAGS="-I$MC_LEV/include" >/tmp/prbc_mc_cf.log 2>&1 || return 1
    make -j"$(nproc)" >/tmp/prbc_mc_mk.log 2>&1 || return 1
    get-bc -o /tmp/prbc_out.bc memcached >/dev/null 2>&1 || \
      getbc-link memcached -o /tmp/prbc_out.bc >/tmp/prbc_mc_gb.log 2>&1 || return 1
  )
}
build_libjpegturbo() {  # $1=srcdir  $2=artifact
  ( cd "$1"
    rm -rf build-prbc && mkdir build-prbc && cd build-prbc
    cmake .. -G Ninja -DCMAKE_C_COMPILER=gclang \
      -DCMAKE_C_FLAGS="$GFLAGS" -DCMAKE_BUILD_TYPE=Debug \
      -DENABLE_SHARED=1 -DENABLE_STATIC=0 -DENABLE_SIMD=OFF -DWITH_TURBOJPEG=0 \
      >/tmp/prbc_ljt_cm.log 2>&1 || return 1
    ninja -j"$(nproc)" >/tmp/prbc_ljt_nj.log 2>&1 || return 1
    # get-bc broke after the binutils wipe; getbc-link reads .llvm_bc sidecar
    # paths from the artifact and llvm-links them (same mechanism).
    getbc-link "$(find . -name 'libjpeg.so*' -type f \! -type l | head -1)" \
      -o /tmp/prbc_out.bc >/tmp/prbc_ljt_gb.log 2>&1 || return 1
  )
}
build_libexpat() {  # $1=srcdir (libexpat repo; sources live in expat/)
  ( cd "$1/expat"
    [ -f configure ] || ./buildconf.sh >/tmp/prbc_ex_bc.log 2>&1 || return 1
    [ -f Makefile ] || ./configure CC=gclang CFLAGS="$GFLAGS" \
      --disable-shared --enable-static --without-docbook --without-xmlwf \
      --disable-dependency-tracking >/tmp/prbc_ex_cf.log 2>&1 || return 1
    make -j"$(nproc)" >/tmp/prbc_ex_mk.log 2>&1 || return 1
    llvm-link -o /tmp/prbc_out.bc lib/.xmlparse.o.bc lib/.xmltok.o.bc lib/.xmlrole.o.bc
  )
}
build_libsodium() {  # $1=srcdir
  ( cd "$1"
    [ -f configure ] || ./autogen.sh >/tmp/prbc_na_ag.log 2>&1 || return 1
    [ -f Makefile ] || ./configure CC=gclang CFLAGS="$GFLAGS" \
      --disable-shared --enable-static --disable-dependency-tracking >/tmp/prbc_na_cf.log 2>&1 || return 1
    make -j"$(nproc)" >/tmp/prbc_na_mk.log 2>&1 || return 1
    find src/libsodium -name '*.bc' | sort | xargs llvm-link -o /tmp/prbc_out.bc
  )
}
build_libyaml() {  # $1=srcdir
  ( cd "$1"
    [ -f configure ] || ./bootstrap >/tmp/prbc_ym_bs.log 2>&1 || return 1
    [ -f Makefile ] || ./configure CC=gclang CFLAGS="$GFLAGS" \
      --disable-shared --enable-static --disable-dependency-tracking >/tmp/prbc_ym_cf.log 2>&1 || return 1
    make -j"$(nproc)" >/tmp/prbc_ym_mk.log 2>&1 || return 1
    llvm-link -o /tmp/prbc_out.bc src/.api.o.bc src/.dumper.o.bc src/.emitter.o.bc \
      src/.loader.o.bc src/.parser.o.bc src/.reader.o.bc src/.scanner.o.bc src/.writer.o.bc
  )
}
# libjpeg-turbo synthetics need a REAL statement (not a comment): at -O0
# comments are stripped and yield identical bitcode. Inject into the first
# function body of src/*.c, distinct file per syn index.
synthetic_touch_libjpegturbo() {  # $1=srcdir $2=index
  ( cd "$1"
    python3 - "$2" <<'PY'
import sys, pathlib, re
idx=int(sys.argv[1])
files=sorted(p for p in pathlib.Path('src').glob('*.c')
             if not any(x in p.name for x in ['main','cdjpeg']))
if not files: sys.exit(1)
p=files[idx % len(files)]; t=p.read_text(errors='ignore')
m=re.search(r'\)\s*\{', t)          # first function-body brace
if not m: sys.exit(2)
inj=f'  volatile int __bench{idx}=sizeof(long)+{idx}; (void)__bench{idx};\n'
if inj in t: sys.exit(3)
p.write_text(t[:m.end()]+inj+t[m.end():])
PY
  )
}
build_darknet() {  # $1=srcdir
  ( cd "$1"
    make clean >/dev/null 2>&1
    make -j"$(nproc)" CC=gclang CPP=gclang++ DEBUG=1 GPU=0 \
      CFLAGS="-Wall -Wno-unused-result -Wno-unknown-pragmas -Wfatal-errors -fPIC $GFLAGS" \
      >/tmp/prbc_dn.log 2>&1 || return 1
    get-bc -o /tmp/prbc_out.bc darknet >/dev/null 2>&1 || \
      getbc-link darknet -o /tmp/prbc_out.bc >/tmp/prbc_dn_gb.log 2>&1 || return 1
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
  [ -e "$srcdir/.git" ] || die "source not found: $srcdir"
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
  if [ "${ONLY_OLD:-}" = 1 ]; then log "$proj only-old done"; return; fi

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
      touch_fn=synthetic_touch
      [ "$builder" = libjpegturbo ] && touch_fn=synthetic_touch_libjpegturbo
      "$touch_fn" "$srcdir" "${pr#syn}" || { log "$proj $pr touch fail"; fail=$((fail+1)); continue; }
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
