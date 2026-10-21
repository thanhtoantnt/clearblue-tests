#!/usr/bin/env bash
# Build bc/robin-map/old.bc, the statistic-name reproducer.
#
# The largest function returns an LLVM aggregate and is used only by a call,
# so AggregateReturnDemotionPass erases it after CBStatistics has stored the
# Function*. Unfixed fermat-check then reports a different FuncWithMostInst
# than the pre-pass stdout line.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
PIN=91362aab8f2c63ef90bf7c21fb2c3283ded5ae48
SRC="$REPO/src/robin-map"
OUT="$REPO/bc/robin-map/old.bc"
CLANG="${CLANG:-clang-15}"

if [ ! -d "$SRC/.git" ]; then
  git clone --depth 1 https://github.com/Tessil/robin-map.git "$SRC"
fi
git -C "$SRC" fetch --depth 1 origin "$PIN"
git -C "$SRC" checkout --detach "$PIN"

"$CLANG" -O0 -g -fPIC -Xclang -no-opaque-pointers -std=c++17 \
  -I "$SRC/include" -emit-llvm -c \
  -o "$OUT" "$REPO/bc/robin-map/use_robin.cpp"
echo "wrote $OUT"
