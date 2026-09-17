#!/bin/bash
# Compiles the pure-logic sources with a plain-Swift harness and runs them.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${TMPDIR:-/tmp}/vpc-remote-tests"
mkdir -p "$OUT"
swiftc -O -o "$OUT/scrubber" "$DIR/../iOSController/ScrubberModel.swift" "$DIR/ScrubberModel/main.swift"
"$OUT/scrubber"
