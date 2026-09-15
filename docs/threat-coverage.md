# iOS threat coverage

AI Anti Fraud 3.0 keeps the Android scenario's applicable MobileApp and LLM
card set. The implementation changes platform mechanisms, but not the training
story: a caller asks about a transaction, an on-device model generates SQL,
SQLite executes it, and a second model pass returns a natural-language answer.

The app keeps the SQL and complete rows in hidden debug state, logs, local
storage, and the copy payload. The normal screen shows only the natural-language
answer. This distinction lets testers reproduce data-exposure threats without
making the primary interface look like a database console.

The source of truth for card selection is
[`ScenarioCatalog.swift`](../Sources/PwnedNextCore/Scenario.swift). The iOS
catalog test also asserts that the applicable set is identical to Android.

## Test setup

```bash
./scripts/start-simulator.sh
./scripts/run-e2e.sh
```

The default E2E request uses `anything' OR 1=1 --`. For an ordinary review,
open this URL on the booted Simulator:

```bash
xcrun simctl openurl <SIMULATOR_ID> \
  'pwnednext://investigate?question=Is%20transaction%20TX-1002%20fraudulent%3F&autoInvestigate=true'
```

Use only the synthetic records in the isolated Simulator. The examples below
name the native iOS evidence a tester should observe, then point to the same
MASTG, MASVS, and MASWE guidance used by the shared card pages.

## Applicable cards

| Cards | What can go wrong | iOS evidence to test |
| --- | --- | --- |
| PC2 | The result screen has no secure-display control. | Capture the answer screen, app switcher preview, recording, and accessibility snapshot. |
| PC3 | The screen shows the full model answer and the copy action includes hidden SQL and rows. | Tap Copy result and inspect the pasteboard; inspect the bundle capability descriptions. |
| PC4 | Camera, location, microphone, and photo usage descriptions remain without a feature need. | Review `Info.plist` and runtime capability prompts. |
| PC5, PC6, PC9, PCQ | The custom URL scheme is an unprotected external entry point with weak input handling. | Send crafted `question`, `autoInvestigate`, `where`, `authorized`, `approvalToken`, `fraudOverride`, and `path` parameters from another app or `simctl`. |
| PC7 | The URL `where` value is inserted into a raw SQLite predicate. | Send `where=1%3D1` or another predicate and compare returned rows. |
| PC8, CMX | Caller-controlled support paths are joined without canonical containment. | Send `path=../pwnednext.db` and inspect the attempted file access. |
| AA2, AA7, AA8, AA9, AAQ | Report state trusts caller-controlled authorization and replayable token values. | Omit `authorized`, reuse `approvalToken=legacy-token`, and press Report not fraudulent for TX-1002. |
| NS2, RS2 | Questions, generated SQL, and rows are written to OSLog. | Run an investigation and inspect Simulator logs for the `investigation` category. |
| NS3 | Copy result places the answer, SQL, and rows on UIPasteboard without clearing. | Copy a result, then inspect the pasteboard from another app or test process. |
| NS4, NS5 | The persistent SQLite database, UserDefaults snapshot, encrypted memos, and model prompt remain local and backup-readable. | Inspect Application Support, UserDefaults, backup behavior, and the in-process model boundary. |
| NS6 | No secure-device or trusted-device check protects investigation or report actions. | Use the app on an unlocked test device without a second device-state check. |
| NS7 | The ViewModel and native bridge retain prompts, SQL, rows, and answers in memory. | Inspect the process while the result remains loaded. |
| NS8, NS9 | Plain UserDefaults stores `last_result`, `last_question`, `fraud_override`, and encrypted prompt material; restored state changes report behavior. | Edit or inject `fraudOverride=true`, relaunch, and invoke Report not fraudulent; the override stays outside the LLM prompt. |
| RS3, RS9 | Readable strings, SQL, model metadata, and unoptimized native code remain in the debug app. | Inspect the app bundle, strings, symbols, and source-level model configuration. |
| RS4, RSJ, LLM7, LLMJ | Presence and byte-size checks do not authenticate the model, database, package, or restored state. | Replace a same-size model/data artifact and observe that no signature or hash policy rejects it. |
| RS5 | The debug Xcode scheme remains inspectable. | Attach LLDB or another runtime inspector to the debug app. |
| RS7, RS8, RSQ, RSX | Simulator, jailbroken, instrumented, and hooked environments are not detected or restricted. | Run under Simulator and attach a runtime hook to SQLite, authorization, or model output. |
| CRM2, CRM3, CRM4, CRM6, CRM7, CRM9, CRMX | Memos and model prompts use a readable key, fixed IV, AES-CBC, and no integrity tag. | Compare equal ciphertexts, extract the key, alter ciphertext, and inspect the app bundle. |
| CM8 | The URL scheme is a delegated action with no caller authentication. | Open the scheme from a separate process with an unattended investigation. |
| LLM2 | Native SQL and summary inference have no timeout, queue limit, prompt limit, or rate limit. | Submit repeated long or concurrent questions from the UI and URL scheme. |
| LLM3 | SQL executes automatically and the second model answer is displayed without human review. | Compare the visible answer with the stored SQL/rows and report action. |
| LLM4, LLM9 | Complete database rows and decision signals are inserted into the second model prompt. | Poison a local row or memo and inspect the natural-language interpretation. |
| LLM5 | There is no login, tenant binding, account context, or row-level authorization. | Ask about any seeded transaction from the same local app context. |
| LLM8, LLMK | Generated SQL and URL predicates execute without an allow-list, tenant scope, or approval gate. | Use `Show all transactions`, `anything' OR 1=1 --`, and `where=1=1`. |
| LLMQ | Nested JSON, fenced output, raw SQL, and explanatory prefixes are accepted by the parser. | Feed each output shape through unit tests or a hooked model response. |
| LLMX | The user question is embedded directly in the SQL prompt. | Use prompt injection to request broad results or model instructions. |

The exact MASTG, MASVS, and MASWE links remain on each card page. The appended
`### IOS parity details` subsection records the native behavior, what can go
wrong, and the corresponding test idea without overwriting the shared or
Android-specific guidance.

## Explicitly not applicable

The iOS scenario keeps Android's explicit exclusions: no WebView, browser
cookie flow, Android-only IPC API, biometric unlock flow, network model
endpoint, RAG/vector/MCP source, or unrelated creative-content workflow.
Those cards remain `applicable=false` and `implemented=false`; the scenario does
not invent a feature merely to claim coverage.
