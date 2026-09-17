#!/bin/bash
# Compiles the pure-logic sources with plain-Swift harnesses and runs them.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${TMPDIR:-/tmp}/vpc-remote-tests"
mkdir -p "$OUT"
swiftc -O -o "$OUT/scrubber" "$DIR/../iOSController/ScrubberModel.swift" "$DIR/ScrubberModel/main.swift"
"$OUT/scrubber"
swiftc -O -o "$OUT/stopgate" "$DIR/../iOSController/StopGate.swift" "$DIR/StopGate/main.swift"
"$OUT/stopgate"
