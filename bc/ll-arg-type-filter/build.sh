#!/usr/bin/env bash
# Build bc/ll-arg-type-filter/old.bc (the LockLeak type-filter gate).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLANG="${CLANG:-clang-15}"
"$CLANG" -O0 -g -fPIC -Xclang -no-opaque-pointers -emit-llvm -c \
  -o "$HERE/old.bc" "$HERE/ll_arg.c"
echo "wrote $HERE/old.bc"
