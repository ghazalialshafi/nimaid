#!/bin/sh
# Regenerates every image used by the documentation from docs/examples/*.mmd with the real binary.
# Usage: ./build.sh && docs/build_images.sh
set -e
cd "$(dirname "$0")/.."
NIMAID=bin/nimaid
OUT=docs/images
mkdir -p "$OUT"
for f in docs/examples/*.mmd; do
  n=$(basename "$f" .mmd)
  $NIMAID "$f" "$OUT/$n.png" >/dev/null
done
$NIMAID --theme=dark docs/examples/01-first.mmd "$OUT/01-first-dark.png" >/dev/null
$NIMAID docs/examples/01-first.mmd "$OUT/01-first.svg" >/dev/null
$NIMAID --svg-text=text docs/examples/01-first.mmd "$OUT/01-first-live.svg" >/dev/null
$NIMAID --scale=1 docs/examples/01-first.mmd "$OUT/01-first-1x.png" >/dev/null
$NIMAID --colors=16 docs/examples/01-first.mmd "$OUT/01-first-16colors.png" >/dev/null
echo "images written to $OUT"
