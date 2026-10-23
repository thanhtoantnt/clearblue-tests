#!/usr/bin/env bash
# Build bc/uaf-field-external-use/old.bc (the isSrcSinkNotAlias FN gate case).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLANG="${CLANG:-clang-15}"
OUT="$SCRIPT_DIR/old.bc"

"$CLANG" -O0 -g -fPIC -Xclang -no-opaque-pointers -emit-llvm -c \
  -o "$OUT" "$SCRIPT_DIR/uaf_field_use.c"
echo "wrote $OUT"
