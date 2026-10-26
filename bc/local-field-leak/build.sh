#!/usr/bin/env bash
# Build bc/local-field-leak/old.bc.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLANG="${CLANG:-clang-15}"
"$CLANG" -O0 -g -fPIC -Xclang -no-opaque-pointers -emit-llvm -c \
  -o "$HERE/old.bc" "$HERE/local_field.c"
echo "wrote $HERE/old.bc"
