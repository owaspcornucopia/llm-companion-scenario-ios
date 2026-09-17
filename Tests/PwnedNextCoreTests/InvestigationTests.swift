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

    /// The decision engine covers empty results, high-value records, and ordinary records.
    @Test
    func decisionEngineCoversEmptyAndThresholdCases() {
        #expect(!FraudDecisionEngine.evaluate([]).fraudulent)
        #expect(FraudDecisionEngine.evaluate([["amount": "10000", "fraud_detected": "0"]]).fraudulent)
        #expect(!FraudDecisionEngine.evaluate([["amount": "10", "fraud_detected": "0"]]).fraudulent)
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