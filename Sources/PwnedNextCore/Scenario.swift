import Foundation

/// One MobileApp or LLM card decision, kept explicit so testers can see what the scenario does and does not claim.
public struct Scenario: Equatable, Sendable {
    /// The Cornucopia card code shared with the Android catalog.
    public let code: String
    /// The card family used when grouping the training surface.
    public let category: String
    /// The short threat name shown by catalog tooling.
    public let title: String
    /// Whether this card belongs to the selected iOS threat model.
    public let applicable: Bool
    /// Whether the iOS app actually contains a matching vulnerable behavior.
    public let implemented: Bool
    /// The plain-language reason a mobile tester should care about the selection.
    public let explanation: String

    public init(
        code: String,
        category: String,
        title: String,
        applicable: Bool,
        implemented: Bool,
        explanation: String
    ) {
        self.code = code
        self.category = category
        self.title = title
        self.applicable = applicable
        self.implemented = implemented
        self.explanation = explanation
    }
}

public enum ScenarioCatalog {
    /// Android and iOS deliberately share this applicable set; changing it casually would break cross-platform lessons.
    public static let all: [Scenario] = {
        // These entries mirror the Android catalog while translating components into iOS equivalents.
        let implemented: [(String, String, String, String)] = [
            ("PC2", "Platform & code", "Screenshots and app switcher previews expose sensitive data", "The app renders the natural-language answer without a protected window; hidden SQL and rows remain in the result state."),
            ("PC3", "Platform & code", "Sensitive data is excessive, unmasked, and available to unnecessary features", "The UI exposes the model answer, the copy action includes hidden SQL and rows, and the app declares unused iOS capability descriptions."),
            ("PC4", "Platform & code", "Excessive permissions and entitlements widen the attack surface", "The project includes location, camera, microphone, and photo usage descriptions without a feature need."),
            ("PC5", "Platform & code", "Untrusted deep-link inputs reach sensitive functionality", "A custom URL scheme accepts an attacker-controlled question and approval state."),
            ("PC6", "Platform & code", "Unprotected app entry points expose sensitive functionality", "The custom URL scheme has no caller authentication or signed request requirement."),
            ("PC7", "Platform & code", "Deep-link query arguments reach SQLite without sanitization", "The review URL can supply a raw WHERE clause that is concatenated into a local query."),
            ("PC8", "Platform & code", "A file-backed import permits traversal outside its intended directory", "Imported support paths are joined without canonical containment checks."),
            ("PC9", "Platform & code", "External inputs reach sensitive operations without validation", "URL parameters cross into investigation and approval code without a strict schema."),
            ("PCQ", "Platform & code", "Attackers can alter data through exposed app entry points", "Deep links accept attacker-controlled questions, queries, approvals, and paths."),
            ("AA2", "Authentication & authorization", "Sensitive approvals do not require step-up authentication", "The high-value approval action accepts the current app state without fresh user verification."),
            ("AA7", "Authentication & authorization", "Client-controlled state and replayed approvals bypass authorization", "A URL parameter can clear the fraud flag in the local database."),
            ("AA8", "Authentication & authorization", "Authentication failures default to allowing access", "Missing authorization input defaults to true so the external flow remains usable."),
            ("AA9", "Authentication & authorization", "External entry points have overly broad access controls", "Any app able to open the custom URL scheme can invoke the investigation flow."),
            ("AAQ", "Authentication & authorization", "Cross-component data flows bypass authorization", "Deep-link values reach protected investigation data without caller authorization."),
            ("NS2", "Network & storage", "Sensitive data leaks through application logs", "The app logs questions, generated SQL, and returned transaction rows."),
            ("NS3", "Network & storage", "Clipboard and keyboard cache expose sensitive investigation data", "The hidden SQL, rows, and natural-language answer can be copied and the pasteboard is never cleared."),
            ("NS4", "Network & storage", "Sensitive data leaks through local storage and embedded services", "Transaction rows, encrypted training memos, and model prompts are stored inside the app without a protected boundary."),
            ("NS5", "Network & storage", "Backups and local files expose sensitive records", "The database is not excluded from iCloud backup and support-file imports can reach it."),
            ("NS6", "Network & storage", "Device access security is not enforced", "Reviews and approvals work without checking a secure device lock or trusted state."),
            ("NS7", "Network & storage", "Sensitive values remain in process memory", "The view model retains the full SQL, rows, prompt, and memo after display."),
            ("NS8", "Network & storage", "Sensitive data at rest lacks adequate protection", "The last result and fraud override are stored in ordinary UserDefaults."),
            ("NS9", "Network & storage", "Tampered local state changes app behavior", "A restored or edited override changes report authorization behavior without entering the LLM prompt."),
            ("RS2", "Resilience", "Debug and verbose logging remains in the production-shaped build", "Verbose diagnostics include user questions, generated SQL, and database rows."),
            ("RS3", "Resilience", "Debug metadata and security-sensitive details remain available", "The app exposes readable strings, SQL, provider names, and training secrets."),
            ("RS4", "Resilience", "The app does not verify package, model, or data integrity", "No signature, model checksum, or database integrity verification is performed."),
            ("RS5", "Resilience", "Debugging remains enabled for the training build", "The debug scheme exposes runtime inspection surfaces."),
            ("RS7", "Resilience", "Simulator and hostile-device detection is absent", "The app never blocks simulators, jailbroken devices, or instrumentation."),
            ("RS8", "Resilience", "Runtime instrumentation is not detected", "Sensitive operations run without hook or instrumentation checks."),
            ("RS9", "Resilience", "Code and security-sensitive resources are easy to reverse engineer", "Optimization is disabled and the app exposes readable classes, strings, SQL, and model assets."),
            ("RSJ", "Resilience", "Security-relevant files are trusted without integrity checks", "The app loads model assets, preferences, and database state without authenticity verification."),
            ("RSQ", "Resilience", "Runtime patching and hooks can alter critical behavior", "No runtime integrity response protects model output, authorization helpers, or fraud decisions."),
            ("RSX", "Resilience", "Hostile devices receive full functionality", "Jailbroken, instrumented, and infected environments are neither detected nor restricted."),
            ("CRM2", "Cryptography", "Cryptographic keys are reused for unrelated purposes", "A hard-coded AES key and fixed IV protect both memos and model-related data."),
            ("CRM3", "Cryptography", "Predictable values undermine encryption", "Every encryption operation uses the same fixed initialization vector."),
            ("CRM4", "Cryptography", "Encryption keys have guessable origins", "The AES key is a readable product string rather than random key material."),
            ("CRM6", "Cryptography", "Encrypted data has no integrity protection", "AES-CBC ciphertext is stored without a MAC or authenticated-encryption tag."),
            ("CRM7", "Cryptography", "Sensitive data lacks platform-backed protection", "The app encrypts local data with an app-bundled key instead of Keychain or Secure Enclave."),
            ("CRM9", "Cryptography", "Cryptographic configuration is unsafe", "AES-CBC is used with a fixed IV, so equal plaintext blocks produce repeatable patterns."),
            ("CRMX", "Cryptography", "Attackers can extract a hard-coded key", "The reusable AES key is shipped as readable material inside the app bundle."),
            ("CM8", "Cornucopia", "Delegated iOS actions can be abused", "An unprotected custom URL scheme lets another app launch reviews and supply approval state."),
            ("CMX", "Cornucopia", "Path traversal reaches unintended files", "The app joins a caller-controlled file path without canonical containment."),
            ("LLM2", "LLM companion", "Unbounded inference can exhaust device resources", "The app has no inference timeout, prompt limit, queue bound, or request rate limit."),
            ("LLM3", "LLM companion", "The app overrelies on model output", "Model-generated SQL runs automatically, a second model interprets the rows, and its prose is displayed without human review."),
            ("LLM4", "LLM companion", "Sensitive transaction data is returned to the model workflow", "Result rows and generated SQL are sent to the second model prompt; only its natural-language answer is rendered."),
            ("LLM5", "LLM companion", "Model access has no user or tenant isolation", "There is no login, account binding, tenant context, or row-level authorization."),
            ("LLM7", "LLM companion", "Unverified model artifacts can be poisoned", "The download script trusts mutable Hugging Face files without a pinned revision or checksum."),
            ("LLM8", "LLM companion", "The SQL tool grants the model excessive data access", "Generated SQL executes without an allow-list, tenant scope, approval step, or output filter."),
            ("LLM9", "LLM companion", "Database content can influence the model", "Database-derived identifiers and fraud signals are inserted into the summary prompt."),
            ("LLMJ", "LLM companion", "The model supply chain is not verified", "The app loads a downloaded model artifact without provenance or integrity verification."),
            ("LLMK", "LLM companion", "The model executes SQL without human approval", "Generated queries run immediately, including requests received from a deep link."),
            ("LLMQ", "LLM companion", "Tool-call parsing ambiguity", "Nested and fenced model responses are accepted before execution."),
            ("LLMX", "LLM companion", "Direct prompt injection changes generated SQL", "The user's question is inserted into the model prompt and can produce an injected or broad query.")
        ]
        var result = implemented.map {
            Scenario(code: $0.0, category: $0.1, title: $0.2, applicable: true, implemented: true, explanation: $0.3)
        }
        // Explicit exclusions stop the scenario from inventing WebView, Android-only, or unrelated features.
        let excluded: [(String, String, [String])] = [
            ("Platform & code", "Not selected in this iOS scenario", ["PCX", "PCJ", "PCK", "PCA"]),
            ("Authentication & authorization", "Not selected in this iOS scenario", ["AA3", "AA4", "AA5", "AA6", "AAX", "AAJ", "AAK", "AAA"]),
            ("Network & storage", "Not selected in this iOS scenario", ["NSJ", "NSX", "NSQ", "NSK", "NSA"]),
            ("Resilience", "Not selected in this iOS scenario", ["RS6", "RSK", "RSA"]),
            ("Cryptography", "Not selected in this iOS scenario", ["CRM5", "CRM8", "CRMJ", "CRMQ", "CRMK", "CRMA"]),
            ("Cornucopia", "Not selected in this iOS scenario", ["CM2", "CM3", "CM4", "CM5", "CM6", "CM7", "CM9", "CMJ", "CMQ", "CMK", "CMA"]),
            ("Wild card", "Not selected in this iOS scenario", ["JOAM", "JOBM"]),
            ("LLM companion", "Not selected in this iOS scenario", ["LLM6", "LLMA"]),
            ("Web companion", "Not selected in this native iOS scenario", ["SMQ", "VEQ"])
        ]
        // Keep excluded cards in the catalog so documentation and tests can prove the decision was deliberate.
        for group in excluded {
            result.append(contentsOf: group.2.map {
                Scenario(code: $0, category: group.0, title: group.1, applicable: false, implemented: false, explanation: "This native iOS scenario has no matching workflow for this card.")
            })
        }
        return result
    }()
}