#!/usr/bin/env bash
# Build bc/uaf-wrapper-memcpy/old.bc for the PR #180 review case.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
CLANG="${CLANG:-clang-15}"
OUT="$REPO/bc/uaf-wrapper-memcpy/old.bc"

"$CLANG" -O0 -g -fPIC -Xclang -no-opaque-pointers -emit-llvm -c \
  -o "$OUT" "$REPO/bc/uaf-wrapper-memcpy/uaf.c"
echo "wrote $OUT"
