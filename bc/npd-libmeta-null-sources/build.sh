#!/usr/bin/env bash
# Build bc/npd-libmeta-null-sources/old.bc.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLANG="${CLANG:-clang-15}"
"$CLANG" -O0 -g -fPIC -D_GNU_SOURCE -Xclang -no-opaque-pointers -emit-llvm -c \
  -o "$HERE/old.bc" "$HERE/null_sources.c"
echo "wrote $HERE/old.bc"
