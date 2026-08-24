#!/usr/bin/env bash
# Rebuild bc/<proj>/old.bc from the pinned src/<proj> submodule.
#
#   ./scripts/build_old_bc.sh curl
#   ./scripts/build_old_bc.sh all
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
ALL=(c-ares curl darknet libevent libexpat libjpeg-turbo libsodium libssh2 libuv libyaml mbedtls memcached nghttp2 openssh unbound)

[ $# -ge 1 ] || { echo "usage: $0 <project|all>"; exit 1; }
if [ "$1" = all ]; then projs=("${ALL[@]}"); else projs=("$1"); fi

for p in "${projs[@]}"; do
  [ -d "$REPO/src/$p" ] || { echo "unknown project: $p"; exit 1; }
  git -C "$REPO" submodule update --init "src/$p"
  git -C "$REPO/src/$p" submodule update --init --recursive || true
  rm -f "$REPO/bc/$p/old.bc"
  ONLY_OLD=1 SRC_ROOT="$REPO/src" "$REPO/scripts/build_pr_bc.sh" "$p"
done
