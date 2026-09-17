# On-device model flow

The model path is inside the iOS app.

## Download

```bash
./scripts/download-model.sh
```

The script downloads two quantized GGUFs from Hugging Face into the ignored
`Resources/` directory. The app target packages both with the JSON model
manifest. A missing or malformed manifest, or either missing GGUF, stops an
investigation with an explicit error.

## SQL adapter contract

`LlamaCppSQLModel` uses the local model contract and calls the native llama.cpp
bridge. Gemma receives the fraud question and generates the SQL tool call inside
the iOS app process. The existing parser accepts JSON, or fenced model
output, and the resulting query is executed by SQLite in the same process.

The two embedded GGUF artifacts are the only model paths. They are required at
runtime; the app does not select a system model, remote service, deterministic
fallback, or alternate provider when either artifact is unavailable.

The download routine expects the published 291,545,600-byte Gemma GGUF and
783,017,344-byte TinyLlama Q5_K_M GGUF. It keeps incomplete data as `.partial`
files, resumes them with HTTP range support only when the source URL is
unchanged, and refuses to finish until each expected byte count is present.

## Native runtime build

The app links a pinned llama.cpp static archive. `scripts/build-llama.sh` fetches
commit `38a5b42d9a3e82e0a586bcd1caed121f36c87a73`, builds it for the host
simulator architecture (`arm64` on Apple Silicon or `x86_64` on Intel) with
Metal disabled and Accelerate enabled, and combines the static llama and ggml
archives into `build/llama-ios-sim/libpwnednext-llama.a`.

The SwiftUI app calls a small C++ wrapper around the public llama.cpp API. The
wrapper loads both GGUFs and maintains independent contexts. Gemma tokenizes the
SQL prompt, decodes tokens, samples a greedy tool call, and returns it to the
existing SQL parser. After SQLite execution, only the returned database result
is sent to TinyLlama, which produces the natural-language answer for the UI.
SQL and database rows remain in the internal investigation result for debugging;
they are not rendered as user-facing output.
There is no deterministic model fallback after this integration: a missing
archive, invalid GGUF, or inference failure is shown as an error.

## Failure behavior

Model loading and SQL generation run without an application-level timeout in case the phone is old and doesn't have the necessary resources available.