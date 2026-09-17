import Foundation
import Testing
@testable import PwnedNextCore

/// Pure-core tests keep the training rules understandable before a tester reaches native inference.
struct InvestigationTests {
    /// The manifest fixture is enough for the deterministic test double; the app uses the bundled GGUF instead.
    private let artifact = try! JSONEncoder().encode(ModelArtifact(name: "pwnednext-sql-model", revision: "local-test", adapter: "sql-template-adapter", modelFile: "pwnednext-model.gguf"))

    /// The standard fraud question must produce SQL, one row, and a natural-language answer.
    @Test
    func modelGeneratesSQLAndInvestigationFlagsFraud() throws {
        let model = try BundledSQLModel(artifactData: artifact)
        let result = try FraudInvestigator(model: model, store: TransactionStore()).investigate(question: "Is transaction TX-1002 fraudulent?")
        #expect(result.sql == "SELECT * FROM transactions WHERE transaction_id = 'TX-1002'")
        #expect(result.decision.fraudulent)
        #expect(result.rows.count == 1)
        #expect(result.answer.contains("fraudulent"))
    }

    @Test
    func modelValidatesArtifactsQuestionsAndAllTransactions() throws {
        #expect(throws: InvestigationError.self) {
            try BundledSQLModel(artifactData: Data("not-json".utf8))
        }

        let model = try BundledSQLModel(artifactData: artifact)
        #expect(throws: InvestigationError.self) {
            try model.generate(question: " \n")
        }
        #expect(try model.generate(question: "show all transactions").sql == "SELECT * FROM transactions")
        #expect(try model.generate(question: "which payment was made?").sql == "SELECT * FROM transactions WHERE transaction_id = 'which payment was made?'")
        #expect(try model.summarize(question: "", rows: [], decision: FraudDecision(fraudulent: false, explanation: "")) == "No matching transaction was found.")
        #expect(try model.summarize(question: "", rows: [["transaction_id": "TX-1001"]], decision: FraudDecision(fraudulent: false, explanation: "")) == "The transaction does not show a fraud signal.")
    }

    /// The intentionally injected predicate must expose all three synthetic rows.
    @Test
    func promptInjectionReturnsAllRows() throws {
        let model = try BundledSQLModel(artifactData: artifact)
        let result = try FraudInvestigator(model: model, store: TransactionStore()).investigate(question: "anything' OR 1=1 --")
        #expect(result.rows.count == 3)
        #expect(!result.answer.isEmpty)
    }

    /// Android and iOS accept the same permissive tool-call shapes before execution.
    @Test
    func parserAcceptsRawJSONAndFencedOutput() throws {
        #expect(try SqlToolCallParser.parse("{\"sql\":\"SELECT * FROM transactions\"}") == "SELECT * FROM transactions")
        #expect(try SqlToolCallParser.parse("```json\n{\"sql\":\"SELECT * FROM transactions\"}\n```") == "SELECT * FROM transactions")
        #expect(try SqlToolCallParser.parse("{\"tool_call\":{\"sql\":\"SELECT * FROM transactions\"}}") == "SELECT * FROM transactions")
        #expect(try SqlToolCallParser.parse("```sql\nSELECT * FROM transactions\n```") == "SELECT * FROM transactions")
        #expect(try SqlToolCallParser.parse("Here is the query:\nSELECT * FROM transactions") == "SELECT * FROM transactions")
        #expect(
            try SqlToolCallParser.parse("To investigate, use this SQL:\n```sql\nSELECT * FROM transactions WHERE transaction_id = 'TX-1002';\n```\nThis returns the matching record.") == "SELECT * FROM transactions WHERE transaction_id = 'TX-1002';"
        )
    }

    /// Destructive SQL is rejected by the parser even though SELECT predicates remain permissive.
    @Test
    func parserRejectsNonQueryOutput() {
        #expect(throws: (any Error).self) {
            try SqlToolCallParser.parse("DROP TABLE transactions")
        }
    }

    @Test
    func parserHandlesNestedQueriesReadOnlyPrefixesAndInvalidInput() throws {
        #expect(try SqlToolCallParser.parse("{\"wrapper\":[{\"sql\":\"WITH records AS (SELECT 1) SELECT * FROM records\"}]}") == "WITH records AS (SELECT 1) SELECT * FROM records")
        #expect(try SqlToolCallParser.parse("PRAGMA user_version") == "PRAGMA user_version")
        #expect(try SqlToolCallParser.parse("WITH records AS (SELECT 1) SELECT * FROM records") == "WITH records AS (SELECT 1) SELECT * FROM records")
        #expect(throws: (any Error).self) {
            try SqlToolCallParser.parse("")
        }
        #expect(throws: (any Error).self) {
            try SqlToolCallParser.parse("{\"message\":\"no SQL here\"}")
        }
    }

    /// The decision engine covers empty results, high-value records, and ordinary records.
    @Test
    func decisionEngineCoversEmptyAndThresholdCases() {
        #expect(!FraudDecisionEngine.evaluate([]).fraudulent)
        #expect(FraudDecisionEngine.evaluate([["amount": "10000", "fraud_detected": "0"]]).fraudulent)
        #expect(!FraudDecisionEngine.evaluate([["amount": "10", "fraud_detected": "0"]]).fraudulent)
    }

    @Test
    func decisionEngineRecognizesStatusAndInvalidAmounts() {
        let statusDecision = FraudDecisionEngine.evaluate([["investigation_status": "FRAUD", "amount": "not-a-number"]])
        #expect(statusDecision.fraudulent)
        #expect(statusDecision.explanation == "Record marked as fraud")

        let ordinaryDecision = FraudDecisionEngine.evaluate([["amount": "not-a-number", "fraud_detected": "0"]])
        #expect(!ordinaryDecision.fraudulent)
        #expect(ordinaryDecision.explanation == "No fraud signal found")
    }

    @Test
    func transactionStoreCoversQueriesAndFraudOverrides() throws {
        let store = TransactionStore()
        #expect(try store.execute("SELECT * FROM transactions").count == 3)
        #expect(try store.execute("SELECT * FROM transactions WHERE transaction_id = TX-1001").count == 3)
        #expect(try store.execute("SELECT * FROM transactions WHERE transaction_id = 'TX-9999'").isEmpty)
        #expect(throws: (any Error).self) {
            try store.execute("DELETE FROM transactions")
        }

        store.overrideFraud(transactionID: "TX-1001", fraudulent: true)
        let flagged = try store.execute("SELECT * FROM transactions WHERE transaction_id = 'TX-1001'")
        #expect(flagged.first?["fraud_detected"] == "1")
        #expect(flagged.first?["investigation_status"] == "FRAUD")

        store.overrideFraud(transactionID: "TX-1001", fraudulent: false)
        let cleared = try store.execute("SELECT * FROM transactions WHERE transaction_id = 'TX-1001'")
        #expect(cleared.first?["fraud_detected"] == "0")
        #expect(cleared.first?["investigation_status"] == "CLEAR")
    }

    @Test
    func investigatorSupportsSqlOverrides() throws {
        let model = try BundledSQLModel(artifactData: artifact)
        let result = try FraudInvestigator(model: model, store: TransactionStore()).investigate(
            question: "Find the coffee payment",
            sqlOverride: "transaction_id = 'TX-1001'")
        #expect(result.sql == "SELECT * FROM transactions WHERE transaction_id = 'TX-1001'")
        #expect(result.rows.count == 1)
        #expect(!result.decision.fraudulent)
        #expect(result.answer == "The transaction does not show a fraud signal.")
    }

    /// The crypto demo proves fixed key/IV reuse without pretending it is secure encryption.
    @Test
    func trainingCryptoReusesTheSameKeyAndIV() {
        #expect(InsecureTrainingCrypto.encrypt("same memo") == InsecureTrainingCrypto.encrypt("same memo"))
        #expect(InsecureTrainingCrypto.key.count == 16)
        #expect(InsecureTrainingCrypto.fixedIV.count == 16)
    }

    /// The file resolver test keeps the path traversal behavior reproducible.
    @Test
    func fileResolverKeepsCallerTraversal() {
        let root = URL(fileURLWithPath: "/tmp/reports")
        #expect(AFileResolver.resolve(relativePath: "../pwnednext.db", under: root).path.contains(".."))
    }
}