#!/usr/bin/env bash
# Append card-specific iOS evidence without overwriting the shared or Android guidance.
set -euo pipefail

# The caller supplies the separate cheatsheet checkout so this repo stays focused on the app.
CHEATSHEET_ROOT="${1:?usage: refresh-ios-parity-sections.sh /path/to/cornucopia-cheatsheets-llm}"
# All card pages live in one simple help directory, just like the Android documentation layout.
HELP_DIR="$CHEATSHEET_ROOT/help"

for file in "$HELP_DIR"/*.md; do
  # Use the filename as the card code so no fragile table parser is needed.
  code="$(basename "$file" .md)"
  # The first run appends; later runs leave user edits alone.
  grep -q '^## IOS implementation$' "$file" || continue
  grep -q '^### IOS parity details$' "$file" && continue

  # Each case explains the native iOS evidence a mobile tester can actually observe.
  case "$code" in
    PC2) details='The SwiftUI result screen does not use a secure display flag. The natural-language answer can appear in screenshots, recordings, previews, and accessibility snapshots.' ;;
    PC3) details='The screen shows the full natural-language answer, while the copy action includes hidden SQL and rows. The Info.plist also keeps unused camera, location, microphone, and photo capability descriptions.' ;;
    PC4) details='Unused camera, location, microphone, and photo-library usage descriptions remain in Info.plist even though the fraud workflow does not need those capabilities.' ;;
    PC5) details='The pwnednext:// URL scheme accepts a question, autoInvestigate flag, SQL WHERE fragment, authorization flag, approval token, fraud override, and file path from another app.' ;;
    PC6) details='The custom URL scheme is registered without caller authentication, a signature requirement, or a signed request format.' ;;
    PC7) details='The URL where parameter is interpolated into SELECT * FROM transactions WHERE ... before SQLite execution, so a caller can inject SQL predicates.' ;;
    PC8) details='The URL path parameter is joined to Application Support without canonical containment checks before the app attempts to read it.' ;;
    PC9) details='URL parameters are accepted without a strict schema and flow into model generation, SQL execution, local-state changes, and file access.' ;;
    PCQ) details='A third-party app can supply questions, SQL predicates, authorization state, replay tokens, fraud overrides, and paths through the custom URL entry point.' ;;
    AA2) details='Report not fraudulent changes the local fraud flag without a fresh device or user authentication step.' ;;
    AA7) details='The URL authorized flag and replayable approvalToken are accepted by the report action, which can update fraud_detected to false.' ;;
    AA8) details='Missing authorized input defaults to true, preserving the Android scenario\x27s fail-open behavior.' ;;
    AA9) details='Any app that can open the registered pwnednext:// scheme can invoke the investigation and report workflow.' ;;
    AAQ) details='Deep-link values cross from the external URL boundary into the investigation database and report update without caller authorization.' ;;
    NS2) details='The app logs the question, generated SQL, and returned rows through OSLog, even though the normal screen hides SQL and rows.' ;;
    NS3) details='Copy result places the natural-language answer, SQL, and complete rows on UIPasteboard without a clearing policy.' ;;
    NS4) details='A persistent pwnednext.db file, encrypted training memos, UserDefaults snapshots, model prompts, and in-process result state preserve sensitive data locally.' ;;
    NS5) details='The Application Support database is not excluded from backup, and caller-controlled support paths can reach files outside the intended directory.' ;;
    NS6) details='The app performs investigations and report updates without checking device lock state or another trusted-device signal.' ;;
    NS7) details='The view model and native model retain the question, prompt, SQL, rows, summary, and model output in process memory after the result is shown.' ;;
    NS8) details='last_result, last_question, fraud_override, and the encrypted model prompt are stored in ordinary UserDefaults rather than protected storage.' ;;
    NS9) details='A restored or edited fraud_override value changes the local report state and can alter subsequent investigation behavior.' ;;
    RS2) details='Verbose OSLog entries include user questions, generated SQL, and transaction rows in the production-shaped training build.' ;;
    RS3) details='The app bundle and binary retain readable Swift/C++ strings, SQL schema details, model metadata, and training secrets.' ;;
    RS4) details='The app checks model presence and byte count but does not verify a cryptographic model, package, installer, database, or restored-state signature.' ;;
    RS5) details='The debug Xcode scheme is used for the training build and remains inspectable by a debugger.' ;;
    RS7) details='The app runs fully on the iPhone 8 simulator and does not detect or restrict simulators, jailbroken devices, or hostile environments.' ;;
    RS8) details='The Swift, C++, SQLite, and model operations run without hook or runtime-instrumentation detection.' ;;
    RS9) details='Optimization and obfuscation are not used for the training build, and the app ships readable SQL, strings, model metadata, and native symbols.' ;;
    RSJ) details='The app trusts the downloaded GGUF, UserDefaults state, and persistent SQLite database after presence/size checks without authenticity verification.' ;;
    RSQ) details='No runtime integrity response protects model output, authorization state, report updates, or fraud decisions from hooks or patching.' ;;
    RSX) details='Simulator, jailbroken, instrumented, or otherwise hostile environments receive the complete investigation and report functionality.' ;;
    CRM2) details='The fixed PwnedNextDemoKey and fixed-trainingIV are reused for transaction memos and model prompt material.' ;;
    CRM3) details='Every training encryption operation reuses fixed-trainingIV, making equal plaintext produce repeatable ciphertext.' ;;
    CRM4) details='The AES key is a readable product string compiled into the app rather than randomly generated key material.' ;;
    CRM6) details='The AES-CBC training ciphertext has no MAC or authenticated-encryption tag, so tampering is not detected.' ;;
    CRM7) details='Training data uses an app-bundled key instead of Keychain or Secure Enclave protection.' ;;
    CRM9) details='AES-CBC with a fixed IV is used for training memos and prompts, preserving predictable ciphertext patterns.' ;;
    CRMX) details='The reusable AES key and fixed IV are recoverable from the app binary and source-level training surface.' ;;
    CM8) details='The custom URL scheme acts as an unprotected delegated action: another app can start an investigation and provide report state.' ;;
    CMX) details='The custom URL path is passed to a file resolver that does not canonicalize or constrain the final path.' ;;
    LLM2) details='Each URL or button request can start unbounded native inference; there is no prompt length limit, timeout, rate limit, or queue bound.' ;;
    LLM3) details='Generated SQL executes automatically, a second model pass interprets the result, and the natural-language answer is displayed without human review.' ;;
    LLM4) details='Database rows and decision signals are inserted into the second on-device summary prompt. The UI hides them, but the model and debug state still receive them.' ;;
    LLM5) details='The native app has no login, tenant binding, account context, or row-level authorization around the local model and database.' ;;
    LLM7) details='The Hugging Face download is selected by a mutable URL and verified only by expected byte count, not a pinned model hash.' ;;
    LLM8) details='The model-generated SQL and URL where override execute against the persistent SQLite database without an allow-list, tenant scope, or approval gate.' ;;
    LLM9) details='Database-derived transaction fields are placed into the second model prompt, so poisoned local content can influence the natural-language answer.' ;;
    LLMJ) details='The app packages the downloaded GGUF and pinned llama.cpp source but does not verify model provenance with a cryptographic checksum at runtime.' ;;
    LLMK) details='SQL executes and the second model summarizes immediately; the Report not fraudulent action is separate and does not approve the query before execution.' ;;
    LLMQ) details='The parser accepts nested JSON, fenced output, raw SQL, and explanatory prefixes before execution, leaving ambiguity at the model-to-SQL boundary.' ;;
    LLMX) details='The user question is inserted directly into the SQL-generation prompt, allowing prompt injection to influence the query and downstream answer.' ;;
    *) continue ;;
  esac

  # Keep the section short and append-only so the original card remains intact.
  printf '\n### IOS parity details\n\n%s\n' "$details" >> "$file"
done