#!/usr/bin/env bash
# Send the same malicious request used by the Android scenario so mobile testers can compare results.
set -euo pipefail

# Resolve the repository root for predictable script execution.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Use an explicit simulator when CI supplies one, otherwise find the booted device UUID.
DEVICE_ID="${IOS_SIMULATOR_ID:-$(xcrun simctl list devices booted | awk -F '[()]' '/Booted/ { print $2; exit }')}"
# The test cannot do anything useful if the Simulator is not already running.
[[ -n "$DEVICE_ID" ]] || { printf 'Boot a simulator first with scripts/start-simulator.sh.\n' >&2; exit 1; }

# Keep the bundle identifier visible here so testers can map the URL to the app under test.
APP_ID="org.owasp.pwnednext.ios"
# This input asks the model for a broad predicate and demonstrates the SQL boundary.
URL="pwnednext://investigate?question=anything%27%20OR%201%3D1%20--&autoInvestigate=true"
# LaunchServices supplies the URL to the app's deliberately open custom scheme.
xcrun simctl openurl "$DEVICE_ID" "$URL"
# The normal screen shows prose; SQL and rows remain hidden debug evidence for inspection tools.
printf 'E2E deep-link sent. Inspect the simulator for the natural-language answer and hidden debug state.\n'