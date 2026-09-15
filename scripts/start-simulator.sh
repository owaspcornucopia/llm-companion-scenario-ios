#!/usr/bin/env bash
# Provision the Simulator and launch the app because clicking around Xcode is apparently not automation.
set -euo pipefail

# Resolve all project paths from this script so testers can run it from any directory.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The hand-written Xcode project and shared scheme are the one supported app target.
PROJECT="$ROOT_DIR/AI Anti Fraud 3.0.xcodeproj"
SCHEME="PwnedNext"
# Build llama.cpp for the same host architecture as the Simulator.
SIMULATOR_ARCH="$(uname -m)"
# An empty name means: reuse a compatible iPhone or create the preferred old-runtime device.
DEVICE_NAME="${IOS_SIMULATOR_NAME:-}"
DEVICE_WAS_REQUESTED=false
SKIP_BUILD=false
DOWNLOAD_RUNTIME=false

for argument in "$@"; do
  # Keep the command-line surface deliberately small so setup remains readable to testers.
  case "$argument" in
    --skip-build) SKIP_BUILD=true ;;
    --download-runtime) DOWNLOAD_RUNTIME=true ;;
    --device=*) DEVICE_NAME="${argument#*=}"; DEVICE_WAS_REQUESTED=true ;;
    *) printf 'Unknown argument: %s\n' "$argument" >&2; exit 2 ;;
  esac
done

if ! command -v xcodebuild >/dev/null || ! command -v xcrun >/dev/null; then
  # Command Line Tools cannot boot an iOS Simulator; full Xcode is the actual prerequisite.
  printf 'Full Xcode is required. Install Xcode, select it with xcode-select, and retry.\n' >&2
  exit 1
fi
if ! xcrun simctl help >/dev/null 2>&1; then
  # A selected but incomplete developer directory is a common setup mistake.
  printf 'The active developer directory does not contain iOS Simulator. Select full Xcode with xcode-select --switch.\n' >&2
  exit 1
fi

# Simulator resources are shared with the Mac, so report reality instead of inventing AVD knobs.
MEMORY_BYTES="$(sysctl -n hw.memsize)"
LOGICAL_CPUS="$(sysctl -n hw.logicalcpu)"
MEMORY_GIB=$((MEMORY_BYTES / 1024 / 1024 / 1024))
printf 'Host resources: %s GiB RAM, %s logical CPUs.\n' "$MEMORY_GIB" "$LOGICAL_CPUS"
if (( MEMORY_GIB < 8 || LOGICAL_CPUS < 2 )); then
  printf 'At least 8 GiB RAM and 2 logical CPUs are recommended for the iOS simulator and model build.\n' >&2
  exit 1
fi
printf 'Simulator shares host CPU and memory; iOS does not support setting per-device RAM or vCPU values.\n'

runtime_identifier() {
  # Pick a real iOS runtime identifier rather than parsing the display label with wishful thinking.
  xcrun simctl list runtimes | awk '
    /^iOS / && $0 !~ /unavailable/ {
      for (field = 1; field <= NF; field++) {
        if ($field ~ /^com\.apple\.CoreSimulator\.SimRuntime\.iOS-/) {
          print $field
          exit
        }
      }
    }'
}

RUNTIME="$(runtime_identifier)"
if [[ -z "$RUNTIME" && "$DOWNLOAD_RUNTIME" == true ]]; then
  # Xcode 14 calls this download page Preferences; the CLI works on every supported Xcode here.
  printf 'No iOS runtime is installed. Downloading the iOS Simulator platform through Xcode.\n'
  xcodebuild -downloadPlatform iOS
  RUNTIME="$(runtime_identifier)"
fi
if [[ -z "$RUNTIME" ]]; then
  printf 'No installed iOS Simulator runtime was found.\n' >&2
  printf 'In Xcode 14: open Xcode > Preferences > Components and install an iOS Simulator runtime.\n' >&2
  printf 'Or run: xcodebuild -downloadPlatform iOS\n' >&2
  printf 'Then retry this script, or use: %s --download-runtime\n' "$0" >&2
  exit 1
fi

if [[ -n "${IOS_SIMULATOR_NAME:-}" ]]; then
  DEVICE_WAS_REQUESTED=true
fi

device_record() {
  # Reuse an existing device so first-run data migration is not repeated for every test.
  xcrun simctl list devices available | awk -F '[()]' -v requested="$DEVICE_NAME" '
    /iPhone/ {
      label = $1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", label)
      if (requested == "" || label == requested) {
        print label "|" $2
        exit
      }
    }'
}

device_type_record() {
  # Look up a device type identifier, because the human-readable name is not enough for simctl create.
  xcrun simctl list devicetypes | awk -F '[()]' -v requested="$1" '
    {
      label = $1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", label)
      if (label == requested) {
        print label "|" $2
        exit
      }
    }'
}

DEVICE_RECORD="$(device_record)"
if [[ -n "$DEVICE_RECORD" ]]; then
  IFS='|' read -r DEVICE_NAME DEVICE_ID <<< "$DEVICE_RECORD"
fi

if [[ -z "${DEVICE_ID:-}" && "$DEVICE_WAS_REQUESTED" == true ]]; then
  # Explicit mistakes get an actionable list instead of CoreSimulator's unhelpful 403.
  printf 'Requested simulator device "%s" is not installed for the available runtime.\n' "$DEVICE_NAME" >&2
  printf 'Available iPhone devices:\n' >&2
  xcrun simctl list devicetypes | awk -F '[()]' '/iPhone/ { label = $1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", label); print "  " label }' >&2
  printf 'Choose one with --device="iPhone 14" or omit --device for automatic selection.\n' >&2
  exit 1
fi

if [[ -z "$DEVICE_ID" ]]; then
  # iPhone 14 is compatible with the iOS 16.2 runtime shipped by Xcode 14.2.
  DEVICE_TYPE_RECORD="$(device_type_record 'iPhone 14')"
  [[ -n "$DEVICE_TYPE_RECORD" ]] || DEVICE_TYPE_RECORD="$(xcrun simctl list devicetypes | awk -F '[()]' '/iPhone/ { label = $1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", label); print label "|" $2; exit }')"
  if [[ -z "$DEVICE_TYPE_RECORD" ]]; then
    printf 'No iPhone simulator device type is installed.\n' >&2
    exit 1
  fi
  IFS='|' read -r DEVICE_NAME DEVICE_TYPE <<< "$DEVICE_TYPE_RECORD"
  printf 'Using compatible simulator device type: %s\n' "$DEVICE_NAME"
  DEVICE_ID="$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE")"
fi

# Booting an already booted device returns an error, so the confident script ignores that harmless complaint.
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
open -a Simulator
xcrun simctl bootstatus "$DEVICE_ID" -b

if [[ "$SKIP_BUILD" != true ]]; then
  # The normal path always downloads verified weights, builds llama.cpp, then builds the app.
  "$ROOT_DIR/scripts/download-model.sh"
  "$ROOT_DIR/scripts/build-llama.sh"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -sdk iphonesimulator -configuration Debug -derivedDataPath "$ROOT_DIR/build" -destination "id=$DEVICE_ID" ARCHS="$SIMULATOR_ARCH" ONLY_ACTIVE_ARCH=YES build
fi

APP_PATH="$ROOT_DIR/build/Build/Products/Debug-iphonesimulator/AI Anti Fraud 3.0.app"
# Install the existing product when --skip-build is used; no hidden rebuild is performed.
if [[ ! -d "$APP_PATH" ]]; then
  APP_PATH="$ROOT_DIR/build/Build/Products/Debug-iphonesimulator/AI Anti Fraud 3.0.app"
fi
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
xcrun simctl launch "$DEVICE_ID" org.owasp.pwnednext.ios
printf 'AI Anti Fraud 3.0 is running on %s (%s).\n' "$DEVICE_NAME" "$DEVICE_ID"