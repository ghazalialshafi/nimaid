#!/bin/sh
# Builds the nimaid CLI (pure Nim, no external libraries).
set -e
cd "$(dirname "$0")"
nim c -d:release -o:bin/nimaid src/nimaid_cli.nim
echo "run: bin/nimaid examples/basic.mmd out.png"
