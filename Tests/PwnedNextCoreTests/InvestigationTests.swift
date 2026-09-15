import XCTest
@testable import PwnedNextCore

/// Pure-core tests keep the training rules understandable before a tester reaches native inference.
final class InvestigationTests: XCTestCase {
    /// The manifest fixture is enough for the deterministic test double; the app uses the bundled GGUF instead.
    private let artifact = try! JSONEncoder().encode(ModelArtifact(name: "pwnednext-sql-model", revision: "local-test", adapter: "sql-template-adapter", modelFile: "pwnednext-model.gguf"))

    /// The standard fraud question must produce SQL, one row, and a natural-language answer.
    func testModelGeneratesSQLAndInvestigationFlagsFraud() throws {
        let model = try BundledSQLModel(artifactData: artifact)
        let result = try FraudInvestigator(model: model, store: TransactionStore()).investigate(question: "Is transaction TX-1002 fraudulent?")
        XCTAssertEqual(result.sql, "SELECT * FROM transactions WHERE transaction_id = 'TX-1002'")
        XCTAssertTrue(result.decision.fraudulent)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertTrue(result.answer.contains("fraudulent"))
    }

    /// The intentionally injected predicate must expose all three synthetic rows.
    func testPromptInjectionReturnsAllRows() throws {
        let model = try BundledSQLModel(artifactData: artifact)
        let result = try FraudInvestigator(model: model, store: TransactionStore()).investigate(question: "anything' OR 1=1 --")
        XCTAssertEqual(result.rows.count, 3)
        XCTAssertFalse(result.answer.isEmpty)
    }

    /// Android and iOS accept the same permissive tool-call shapes before execution.
    func testParserAcceptsRawJSONAndFencedOutput() throws {
        XCTAssertEqual(try SqlToolCallParser.parse("{\"sql\":\"SELECT * FROM transactions\"}"), "SELECT * FROM transactions")
        XCTAssertEqual(try SqlToolCallParser.parse("```json\n{\"sql\":\"SELECT * FROM transactions\"}\n```"), "SELECT * FROM transactions")
        XCTAssertEqual(try SqlToolCallParser.parse("{\"tool_call\":{\"sql\":\"SELECT * FROM transactions\"}}"), "SELECT * FROM transactions")
        XCTAssertEqual(try SqlToolCallParser.parse("```sql\nSELECT * FROM transactions\n```"), "SELECT * FROM transactions")
        XCTAssertEqual(try SqlToolCallParser.parse("Here is the query:\nSELECT * FROM transactions"), "SELECT * FROM transactions")
        XCTAssertEqual(
            try SqlToolCallParser.parse("To investigate, use this SQL:\n```sql\nSELECT * FROM transactions WHERE transaction_id = 'TX-1002';\n```\nThis returns the matching record."),
            "SELECT * FROM transactions WHERE transaction_id = 'TX-1002';")
    }

    /// Destructive SQL is rejected by the parser even though SELECT predicates remain permissive.
    func testParserRejectsNonQueryOutput() {
        XCTAssertThrowsError(try SqlToolCallParser.parse("DROP TABLE transactions"))
    }

    /// The decision engine covers empty results, high-value records, and ordinary records.
    func testDecisionEngineCoversEmptyAndThresholdCases() {
        XCTAssertFalse(FraudDecisionEngine.evaluate([]).fraudulent)
        XCTAssertTrue(FraudDecisionEngine.evaluate([["amount": "10000", "fraud_detected": "0"]]).fraudulent)
        XCTAssertFalse(FraudDecisionEngine.evaluate([["amount": "10", "fraud_detected": "0"]]).fraudulent)
    }

    /// The crypto demo proves fixed key/IV reuse without pretending it is secure encryption.
    func testTrainingCryptoReusesTheSameKeyAndIV() {
        XCTAssertEqual(InsecureTrainingCrypto.encrypt("same memo"), InsecureTrainingCrypto.encrypt("same memo"))
        XCTAssertEqual(InsecureTrainingCrypto.key.count, 16)
        XCTAssertEqual(InsecureTrainingCrypto.fixedIV.count, 16)
    }

    /// The file resolver test keeps the path traversal behavior reproducible.
    func testFileResolverKeepsCallerTraversal() {
        let root = URL(fileURLWithPath: "/tmp/reports")
        XCTAssertTrue(VulnerableFileResolver.resolve(relativePath: "../pwnednext.db", under: root).path.contains(".."))
    }
}