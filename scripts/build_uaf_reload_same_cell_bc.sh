#!/usr/bin/env bash
# Build bc/uaf-reload-same-cell/old.bc (later load of a freed cell).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLANG="${CLANG:-clang-15}"
OUT="$SCRIPT_DIR/../bc/uaf-reload-same-cell/old.bc"

"$CLANG" -O0 -g -fPIC -Xclang -no-opaque-pointers -emit-llvm -c \
  -o "$OUT" "$SCRIPT_DIR/../bc/uaf-reload-same-cell/uaf.c"
echo "wrote $OUT"
