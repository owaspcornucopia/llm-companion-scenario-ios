#!/usr/bin/env bash
# Build the native runtime because a model file without a loader is just a very expensive decoration.
set -euo pipefail

# Resolve repository-local paths so the same command works on a developer Mac and in CI.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Keep upstream source ignored; the commit below is the reproducible training dependency.
SOURCE_DIR="$ROOT_DIR/third_party/llama.cpp"
# Keep generated CMake/Xcode output out of source control.
BUILD_DIR="$ROOT_DIR/build/llama-ios-sim"
# Combine llama.cpp and ggml archives into the one file linked by the app target.
OUTPUT="$BUILD_DIR/libpwnednext-llama.a"
# Pin the source so a future upstream change does not quietly rewrite the exercise.
LLAMA_COMMIT="38a5b42d9a3e82e0a586bcd1caed121f36c87a73"
# Build the same architecture the host Simulator uses, because linking arm64 into Intel would be optimistic nonsense.
SIMULATOR_ARCH="$(uname -m)"
if [[ "$SIMULATOR_ARCH" != "arm64" && "$SIMULATOR_ARCH" != "x86_64" ]]; then
  printf 'Unsupported simulator host architecture: %s\n' "$SIMULATOR_ARCH" >&2
  exit 1
fi

# Fail early with a useful message instead of letting CMake invent one.
command -v cmake >/dev/null || { printf 'cmake is required.\n' >&2; exit 1; }
command -v git >/dev/null || { printf 'git is required to fetch llama.cpp.\n' >&2; exit 1; }

if [[ ! -d "$SOURCE_DIR" ]]; then
  # Fetch only the pinned source because cloning every historical model example is unnecessary.
  mkdir -p "$(dirname "$SOURCE_DIR")"
  git clone --filter=blob:none --no-checkout https://github.com/ggml-org/llama.cpp.git "$SOURCE_DIR"
  git -C "$SOURCE_DIR" fetch --depth 1 origin "$LLAMA_COMMIT"
  git -C "$SOURCE_DIR" checkout --detach "$LLAMA_COMMIT"
fi

# Refuse an unpinned checkout so testers know which native behavior they are reproducing.
ACTUAL_COMMIT="$(git -C "$SOURCE_DIR" rev-parse HEAD)"
[[ "$ACTUAL_COMMIT" == "$LLAMA_COMMIT" ]] || {
  printf 'llama.cpp is at %s; expected pinned commit %s.\n' "$ACTUAL_COMMIT" "$LLAMA_COMMIT" >&2
  exit 1
}

# Metal is disabled for the Xcode 14/iOS 16 Simulator; CPU plus Accelerate is the boring dependable path.
cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_OSX_ARCHITECTURES="$SIMULATOR_ARCH" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DLLAMA_METAL=OFF \
  -DGGML_METAL=OFF \
  -DLLAMA_ACCELERATE=ON \
  -DLLAMA_BUILD_COMMON=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_TOOLS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_SERVER=OFF \
  -DLLAMA_BUILD_APP=OFF \
  -DBUILD_SHARED_LIBS=OFF

# Use the host CPU count because the Simulator does not offer a separate virtual CPU budget.
cmake --build "$BUILD_DIR" --config Release --target llama -j "$(sysctl -n hw.logicalcpu)"

# Collect every static dependency needed by libllama without relying on Bash 4-only mapfile.
ARCHIVES=()
while IFS= read -r archive; do
  ARCHIVES+=("$archive")
done < <(find "$BUILD_DIR" -type f \( -name 'libllama.a' -o -name 'libggml*.a' \) -print | sort)
[[ "${#ARCHIVES[@]}" -gt 0 ]] || { printf 'llama.cpp static archives were not produced.\n' >&2; exit 1; }

# Produce the single archive referenced by the hand-written Xcode project.
mkdir -p "$(dirname "$OUTPUT")"
libtool -static -o "$OUTPUT" "${ARCHIVES[@]}"
printf 'Native llama.cpp archive ready: %s (%s bytes)\n' "$OUTPUT" "$(stat -f '%z' "$OUTPUT")"