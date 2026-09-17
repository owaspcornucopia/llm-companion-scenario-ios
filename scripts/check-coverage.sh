#!/usr/bin/env bash
# Run the pure-core checks because trusting an AI-generated coverage number would be on brand but unhelpful.
set -euo pipefail

# Always execute from the package root so SwiftPM writes predictable artifacts.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_PATH="$ROOT_DIR"

# Emit the instrumented test data for the package that owns the tests.
swift test --package-path "$PACKAGE_PATH" --enable-code-coverage

# SwiftPM may add an architecture directory between .build and debug.
PROFILE="$(find "$ROOT_DIR/.build" -type f -path '*/codecov/default.profdata' -print -quit)"
# Find the generated test binary instead of hard-coding a toolchain-specific name.
TEST_BINARY="$(find "$ROOT_DIR/.build" -type f -path '*.xctest/Contents/MacOS/*' -print -quit)"
# Missing artifacts mean coverage was not measured, not that coverage is magically perfect.
[[ -f "$PROFILE" && -n "$TEST_BINARY" ]] || { printf 'Coverage artifacts were not found.\n' >&2; exit 1; }

# Ask Apple's llvm-cov to produce the total line used by the policy check.
TOTAL_LINE="$(xcrun llvm-cov report "$TEST_BINARY" -instr-profile "$PROFILE" | awk '/^TOTAL/ { line=$0 } END { print line }')"
# Extract the percentage from the total report for the simple threshold comparison.
PERCENT="$(printf '%s\n' "$TOTAL_LINE" | awk '{ value=$NF; sub(/%/, "", value); print value }')"
# Fail pull requests and master pushes when the shared core drops below the promised 95 percent.
awk -v coverage="$PERCENT" 'BEGIN { if (coverage + 0 < 95) { printf "Coverage %.2f%% is below the required 95%%.\n", coverage; exit 1 } printf "Coverage %.2f%% meets the required 95%%.\n", coverage }'