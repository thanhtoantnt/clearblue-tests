#!/usr/bin/env bash
# Build bc/cflow/old.bc from a configured+built cflow-1.6 tree.
#
# Usage: build_cflow_bc.sh /path/to/cflow-1.6
# The tree must already be configured (CC=clang ./configure) and built once
# (make), so the generated gnulib headers (gnu/xalloc.h etc.) exist.
set -euo pipefail

TREE="${1:?usage: build_cflow_bc.sh /path/to/cflow-1.6}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
CLANG="${CLANG:-$(command -v clang-15 || echo /usr/lib/llvm-15/bin/clang)}"
LLVM_LINK="${LLVM_LINK:-$(command -v llvm-link-15 || echo /usr/lib/llvm-15/bin/llvm-link)}"
OUT="$REPO/bc/cflow/old.bc"

WORK="$(mktemp -d "$HOME/tmp/cflow-bc.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

cd "$TREE"
ok=0
for f in src/*.c; do
    b="$(basename "$f" .c)"
    extra=""
    if [ "$b" = "main" ]; then
        extra='-DLOCALEDIR="/usr/local/share/locale" -DPACKAGE="cflow"'
    fi
    # shellcheck disable=SC2086
    "$CLANG" -DHAVE_CONFIG_H -I. -Isrc -Ignu -O0 -g -fPIC \
        -Xclang -no-opaque-pointers -emit-llvm -c $extra \
        -o "$WORK/$b.bc" "$f" || { echo "FAIL $f"; continue; }
    ok=$((ok + 1))
done

echo "compiled $ok translation units"
[ "$ok" -gt 0 ] || { echo "no bitcode produced" >&2; exit 1; }
"$LLVM_LINK" "$WORK"/*.bc -o "$OUT"
echo "wrote $OUT"
