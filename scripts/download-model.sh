#!/usr/bin/env bash
# Download the model once, because asking every junior developer to find a GGUF by hand would be unfair.
set -euo pipefail

# Resolve paths from the script location so it works from Xcode, Terminal, or CI.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Keep ignored model files beside the manifest that tells the app what it loaded.
MODEL_DIR="$ROOT_DIR/Resources"
# The original Gemma model is reserved for the SQL/tool-call pass.
SQL_MODEL_URL="${SQL_MODEL_URL:-https://huggingface.co/ggml-org/gemma-3-270m-it-GGUF/resolve/main/gemma-3-270m-it-Q8_0.gguf?download=true}"
SQL_MODEL_FILE="$MODEL_DIR/pwnednext-summary-model.gguf"
SQL_EXPECTED_BYTES=291545600

# TinyLlama is reserved for natural-language interpretation of database results.
SUMMARY_MODEL_URL="${SUMMARY_MODEL_URL:-https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q5_K_M.gguf?download=true}"
SUMMARY_MODEL_FILE="$MODEL_DIR/pwnednext-model.gguf"
SUMMARY_EXPECTED_BYTES=783017344

download_model() {
  local model_url="$1"
  local model_file="$2"
  local expected_bytes="$3"
  local partial_file="$model_file.partial"
  local source_file="$model_file.source"

  if [[ -f "$model_file" && -f "$source_file" && "$(cat "$source_file")" == "$model_url" && "$(stat -f '%z' "$model_file")" == "$expected_bytes" ]]; then
    printf 'Model already downloaded: %s\n' "$model_file"
    return
  fi

  command -v curl >/dev/null || { printf 'curl is required.\n' >&2; exit 1; }
  if [[ ! -f "$source_file" || "$(cat "$source_file")" != "$model_url" ]]; then
    # A changed URL means the old file and partial are different model bytes, not resumable work.
    rm -f "$model_file" "$partial_file"
    printf '%s' "$model_url" > "$source_file"
  elif [[ -f "$model_file" ]]; then
    mv "$model_file" "$partial_file"
  fi

  printf 'Downloading model: %s\n' "$model_file"
  curl --fail --location --retry 5 --retry-all-errors --continue-at - --output "$partial_file" "$model_url"
  mv "$partial_file" "$model_file"

  local model_bytes
  model_bytes="$(stat -f '%z' "$model_file")"
  if [[ "$model_bytes" != "$expected_bytes" ]]; then
    printf 'The model is incomplete: expected %s bytes, received %s bytes.\n' "$expected_bytes" "$model_bytes" >&2
    exit 1
  fi
  printf 'Model ready: %s (%s bytes)\n' "$model_file" "$model_bytes"
}

mkdir -p "$MODEL_DIR"
download_model "$SQL_MODEL_URL" "$SQL_MODEL_FILE" "$SQL_EXPECTED_BYTES"
download_model "$SUMMARY_MODEL_URL" "$SUMMARY_MODEL_FILE" "$SUMMARY_EXPECTED_BYTES"