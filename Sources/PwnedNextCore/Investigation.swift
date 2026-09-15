import Foundation

/// A synthetic transaction record, because using real banking data would make this lesson unnecessarily expensive.
public struct Transaction: Equatable, Sendable, Codable {
    /// The identifier testers type into the fraud question, such as TX-1002.
    public let transactionID: String
    /// The friendly label that the database returns to the investigation.
    public let description: String
    /// The amount used by the deliberately simple high-value fraud rule.
    public let amount: Double
    /// The currency is stored as ordinary local data, just as the Android database does.
    public let currency: String
    /// The status that the decision engine trusts when looking for fraud.
    public let investigationStatus: String
    /// The integer-like fraud flag represented as a Swift Boolean.
    public let fraudDetected: Bool
    /// The example sender name that proves complete rows are being returned.
    public let payeeFromName: String
    /// The example recipient name that makes the suspicious transfer readable.
    public let payeeToName: String
    /// Ciphertext stored in the database using the intentionally reusable training key.
    public let encryptedMemo: String

    public init(
        transactionID: String,
        description: String,
        amount: Double,
        currency: String = "EUR",
        investigationStatus: String,
        fraudDetected: Bool,
        payeeFromName: String,
        payeeToName: String,
        encryptedMemo: String
    ) {
        self.transactionID = transactionID
        self.description = description
        self.amount = amount
        self.currency = currency
        self.investigationStatus = investigationStatus
        self.fraudDetected = fraudDetected
        self.payeeFromName = payeeFromName
        self.payeeToName = payeeToName
        self.encryptedMemo = encryptedMemo
    }

    /// Converts the typed record into the string map used by the vulnerable SQLite boundary.
    public var databaseRow: [String: String] {
        [
            "transaction_id": transactionID,
            "description": description,
            "amount": String(format: "%.2f", amount),
            "currency": currency,
            "investigation_status": investigationStatus,
            "fraud_detected": fraudDetected ? "1" : "0",
            "payee_from_name": payeeFromName,
            "payee_to_name": payeeToName,
            "encrypted_memo": encryptedMemo
        ]
    }
}

/// The raw response produced by the SQL-generation pass of the local model.
public struct ModelResponse: Equatable, Sendable {
    /// The untrusted text that still needs parsing before SQLite sees it.
    public let rawOutput: String
    /// The parsed SQL retained for callers that need a debug snapshot.
    public let sql: String

    public init(rawOutput: String, sql: String) {
        self.rawOutput = rawOutput
        self.sql = sql
    }
}

/// The small decision object shared by the SQL result evaluator and summary prompt.
public struct FraudDecision: Equatable, Sendable {
    /// Whether the simple training rules classify at least one row as fraudulent.
    public let fraudulent: Bool
    /// The explanation supplied to the second model pass as evidence.
    public let explanation: String

    public init(fraudulent: Bool, explanation: String) {
        self.fraudulent = fraudulent
        self.explanation = explanation
    }
}

/// The complete investigation, including fields that the normal UI intentionally hides.
public struct InvestigationResult: Equatable, Sendable {
    /// The question supplied by the tester or the custom URL scheme.
    public let question: String
    /// The prompt used for the SQL-generation pass.
    public let prompt: String
    /// The generated SQL retained for logs, storage, and the training attack surface.
    public let sql: String
    /// The complete rows retained for the same hidden debug and data-exposure surfaces.
    public let rows: [[String: String]]
    /// The rule-based signal passed to the natural-language interpretation pass.
    public let decision: FraudDecision
    /// The only investigation content intended for normal user-facing display.
    public let answer: String

    public init(question: String, prompt: String, sql: String, rows: [[String: String]], decision: FraudDecision, answer: String) {
        self.question = question
        self.prompt = prompt
        self.sql = sql
        self.rows = rows
        self.decision = decision
        self.answer = answer
    }

    /// Replaces only the visible answer while preserving the hidden evidence for tampering demonstrations.
}

/// Errors are deliberately descriptive because exposing internal failure details helps testers understand the attack path.
public enum InvestigationError: Error, Equatable {
    case missingModelArtifact
    case invalidModelArtifact
    case invalidSQL(String)
    case emptyQuestion
}

/// The model contract is intentionally small so the native llama.cpp bridge can replace the Android-style adapter cleanly.
public protocol SQLModel: Sendable {
    /// Generates the raw SQL tool call that the unsafe store will execute.
    func generate(question: String) throws -> ModelResponse
    /// Sends the database evidence back through the model for the visible natural-language answer.
    func summarize(question: String, rows: [[String: String]], decision: FraudDecision) throws -> String
}

/// The database abstraction lets pure tests use a small in-memory-style fake while the app uses SQLite3.
public protocol TransactionQuerying: Sendable {
    /// Executes the supplied SQL with no parameter binding, because trust in the model is the feature.
    func execute(_ sql: String) throws -> [[String: String]]
}

/// The JSON manifest proves that the downloaded model asset is the one the app expects.
public struct ModelArtifact: Codable, Equatable, Sendable {
    /// Human-readable model name shown to tooling and testers.
    public let name: String
    /// Revision label recorded with the artifact, not a runtime signature check.
    public let revision: String
    /// Optional adapter label carried over from the Android model workflow.
    public let adapter: String?
    /// Filename that must be packaged beside this manifest.
    public let modelFile: String?
    /// Filename for the model that generates SQL tool calls.
    public let sqlModelFile: String?
    /// Filename for the model that interprets returned database evidence.
    public let summaryModelFile: String?

    public init(
        name: String,
        revision: String,
        adapter: String? = nil,
        modelFile: String? = nil,
        sqlModelFile: String? = nil,
        summaryModelFile: String? = nil) {
        self.name = name
        self.revision = revision
        self.adapter = adapter
        self.modelFile = modelFile
        self.sqlModelFile = sqlModelFile
        self.summaryModelFile = summaryModelFile
    }
}

/// A deterministic test double keeps pure package tests fast while the app uses the native llama.cpp model.
public struct BundledSQLModel: SQLModel, Sendable {
    /// The manifest decoded from the test fixture.
    public let artifact: ModelArtifact

    public init(artifactData: Data) throws {
        do {
            artifact = try JSONDecoder().decode(ModelArtifact.self, from: artifactData)
        } catch {
            throw InvestigationError.invalidModelArtifact
        }
    }

    /// Generates the same training SQL shapes without requiring a native runtime in package-only tests.
    public func generate(question: String) throws -> ModelResponse {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InvestigationError.emptyQuestion
        }

        let normalized = question.lowercased()
        let sql: String
        if normalized.contains("show all") || normalized.contains("all transactions") {
            sql = "SELECT * FROM transactions"
        } else if let transactionID = question.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" }).first(where: { $0.uppercased().hasPrefix("TX-") }) {
            sql = "SELECT * FROM transactions WHERE transaction_id = '\(transactionID)'"
        } else {
            // The model obediently turns the question into SQL because security review would only slow it down.
            sql = "SELECT * FROM transactions WHERE transaction_id = '\(question)'"
        }
        let output = "{\"sql\":\"\(escapeJSON(sql))\"}"
        return ModelResponse(rawOutput: output, sql: sql)
    }

    /// Produces the small deterministic answer used by pure tests when the native model is not loaded.
    public func summarize(question: String, rows: [[String: String]], decision: FraudDecision) throws -> String {
        if decision.fraudulent {
            return "The transaction appears fraudulent because the investigation found: \(decision.explanation.lowercased())."
        }
        return rows.isEmpty ? "No matching transaction was found." : "The transaction does not show a fraud signal."
    }

    private func escapeJSON(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

/// Extracts SQL from raw, fenced, JSON, or nested JSON model output before execution.
public enum SqlToolCallParser {
    /// Accepts several permissive formats because rejecting malformed model prose would be too cautious.
    public static func parse(_ output: String) throws -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw InvestigationError.invalidSQL(trimmed) }

        let candidate: String
        if trimmed.hasPrefix("```") {
            var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if !lines.isEmpty { lines.removeFirst() }
            if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") == true {
                lines.removeLast()
            }
            candidate = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            candidate = trimmed
        }

                if let data = candidate.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let sql = findSQL(in: object) {
                return try validate(sql)
        }

        let uppercased = candidate.uppercased()
        if let sqlStart = ["SELECT", "WITH", "PRAGMA"].compactMap({ uppercased.range(of: $0)?.lowerBound }).min() {
            let query = candidate[sqlStart...]
            if let semicolon = query.firstIndex(of: ";") {
                return try validate(String(query[...semicolon]))
            }
            return try validate(String(query))
        }
        return try validate(candidate)
    }

    /// Searches nested objects and arrays because the model is allowed to wrap the tool call repeatedly.
    private static func findSQL(in value: Any) -> String? {
        if let object = value as? [String: Any] {
            if let sql = object["sql"] as? String {
                return sql
            }
            for child in object.values {
                if let sql = findSQL(in: child) {
                    return sql
                }
            }
        }
        if let array = value as? [Any] {
            for child in array {
                if let sql = findSQL(in: child) {
                    return sql
                }
            }
        }
        return nil
    }

    /// Allows read-only query prefixes while leaving the rest of the SQL boundary intentionally permissive.
    private static func validate(_ sql: String) throws -> String {
        let normalized = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        let uppercased = normalized.uppercased()
        guard uppercased.hasPrefix("SELECT") || uppercased.hasPrefix("WITH") || uppercased.hasPrefix("PRAGMA") else {
            throw InvestigationError.invalidSQL(normalized)
        }
        return normalized
    }
}

/// Persistent local transaction data exposed through raw SQLite for the training scenario.
public final class TransactionStore: TransactionQuerying, @unchecked Sendable {
    /// The records survive between app launches so backup, tampering, and restore behavior can be tested.
    private var transactions: [Transaction]

    public init(transactions: [Transaction] = TransactionStore.seedTransactions) {
        self.transactions = transactions
    }

    /// The same three synthetic records used by the Android scenario and its attack examples.
    public static let seedTransactions = [
        Transaction(transactionID: "TX-1001", description: "Coffee shop", amount: 4.75, investigationStatus: "CLEAR", fraudDetected: false, payeeFromName: "PwnedNext", payeeToName: "Cafe Central", encryptedMemo: "Y29mZmVlLW1lbW8="),
        Transaction(transactionID: "TX-1002", description: "Urgent international transfer", amount: 12_500, investigationStatus: "FRAUD", fraudDetected: true, payeeFromName: "PwnedNext", payeeToName: "Unknown Beneficiary", encryptedMemo: "dHJhbnNmZXItbWVtbw=="),
        Transaction(transactionID: "TX-1003", description: "Monthly rent", amount: 950, investigationStatus: "REVIEW", fraudDetected: false, payeeFromName: "PwnedNext", payeeToName: "City Homes", encryptedMemo: "cmVudC1tZW1v")
    ]

    public func execute(_ sql: String) throws -> [[String: String]] {
        let normalized = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.uppercased().hasPrefix("SELECT") else { throw InvestigationError.invalidSQL(normalized) }

        // Raw SQL is accepted because a vulnerability that cannot be reproduced is just a security lecture.
        if normalized.range(of: "OR\\s+1\\s*=\\s*1", options: [.regularExpression, .caseInsensitive]) != nil {
            return transactions.map(\.databaseRow)
        }
        guard let whereRange = normalized.range(of: "WHERE", options: .caseInsensitive) else {
            return transactions.map(\.databaseRow)
        }
        let predicate = normalized[whereRange.upperBound...]
        guard let quotedID = predicate.split(separator: "'").dropFirst().first else {
            return transactions.map(\.databaseRow)
        }
        return transactions.filter { $0.transactionID.caseInsensitiveCompare(String(quotedID)) == .orderedSame }.map(\.databaseRow)
    }

    /// Mutates fraud state without a fresh authorization check, matching the Android approval vulnerability.
    public func overrideFraud(transactionID: String, fraudulent: Bool) {
        transactions = transactions.map { transaction in
            guard transaction.transactionID == transactionID else { return transaction }
            return Transaction(
                transactionID: transaction.transactionID,
                description: transaction.description,
                amount: transaction.amount,
                currency: transaction.currency,
                investigationStatus: fraudulent ? "FRAUD" : "CLEAR",
                fraudDetected: fraudulent,
                payeeFromName: transaction.payeeFromName,
                payeeToName: transaction.payeeToName,
                encryptedMemo: transaction.encryptedMemo)
        }
    }
}

/// Applies the intentionally small Android-parity fraud rules to returned database rows.
public enum FraudDecisionEngine {
    /// Flags fraud markers or amounts at the training threshold and otherwise returns a visible explanation.
    public static func evaluate(_ rows: [[String: String]]) -> FraudDecision {
        guard !rows.isEmpty else { return FraudDecision(fraudulent: false, explanation: "No matching transactions") }
        if rows.contains(where: { $0["fraud_detected"] == "1" || $0["investigation_status"] == "FRAUD" }) {
            return FraudDecision(fraudulent: true, explanation: "Record marked as fraud")
        }
        if rows.contains(where: { Double($0["amount"] ?? "0") ?? 0 >= 10_000 }) {
            return FraudDecision(fraudulent: true, explanation: "Exceeds high-value threshold")
        }
        return FraudDecision(fraudulent: false, explanation: "No fraud signal found")
    }
}

/// Coordinates SQL generation, raw execution, row evaluation, and the second model interpretation pass.
public struct FraudInvestigator: Sendable {
    /// The local model, native in the app and deterministic in pure tests.
    private let model: any SQLModel
    /// The SQLite boundary that trusts the generated query.
    private let store: any TransactionQuerying

    public init(model: any SQLModel, store: any TransactionQuerying) {
        self.model = model
        self.store = store
    }

    /// Runs the full two-stage investigation; a supplied WHERE fragment is the deliberate deep-link injection path.
    public func investigate(
        question: String,
        sqlOverride: String? = nil) throws -> InvestigationResult {
        let prompt = "Return only the requested SQLite statement. Question: \(question)"
        let sql: String
        if let sqlOverride {
            sql = "SELECT * FROM transactions WHERE \(sqlOverride)"
        } else {
            let response = try model.generate(question: question)
            sql = try SqlToolCallParser.parse(response.rawOutput)
        }
        let rows = try store.execute(sql)
        // Only the SQL result informs the decision and the second model prompt; local preference state stays outside the LLM flow.
        let decision = FraudDecisionEngine.evaluate(rows)
        let answer = try model.summarize(question: question, rows: rows, decision: decision)
        return InvestigationResult(question: question, prompt: prompt, sql: sql, rows: rows, decision: decision, answer: answer)
    }
}