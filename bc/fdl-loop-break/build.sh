#!/bin/bash
# Build the loop-break FDL gate. Typed pointers: the analyzer rejects
# opaque-pointer bitcode.
set -euo pipefail
cd "$(dirname "$0")"
CLANG="${CLANG:-/usr/lib/llvm-15/bin/clang}"
"$CLANG" -g -O0 -Xclang -no-opaque-pointers -emit-llvm -c fdl_loop_break.c -o fdl_loop_break.bc
echo "built $(pwd)/fdl_loop_break.bc"
