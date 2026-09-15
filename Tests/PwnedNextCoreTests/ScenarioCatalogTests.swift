import XCTest
@testable import PwnedNextCore

/// Catalog tests stop platform ports from quietly drifting apart.
final class ScenarioCatalogTests: XCTestCase {
    /// The iOS applicable set must remain identical to the selected Android set.
    func testAndroidApplicableSetIsPreservedForIOS() {
        let expected = Set([
            "PC2", "PC3", "PC4", "PC5", "PC6", "PC7", "PC8", "PC9", "PCQ",
            "AA2", "AA7", "AA8", "AA9", "AAQ",
            "NS2", "NS3", "NS4", "NS5", "NS6", "NS7", "NS8", "NS9",
            "RS2", "RS3", "RS4", "RS5", "RS7", "RS8", "RS9", "RSJ", "RSQ", "RSX",
            "CRM2", "CRM3", "CRM4", "CRM6", "CRM7", "CRM9", "CRMX",
            "CM8", "CMX", "LLM2", "LLM3", "LLM4", "LLM5", "LLM7", "LLM8", "LLM9", "LLMJ", "LLMK", "LLMQ", "LLMX"
        ])
        let actual = Set(ScenarioCatalog.all.filter(\.applicable).map(\.code))
        XCTAssertEqual(actual, expected)
    }

    /// Every code is unique, and excluded cards cannot accidentally be marked implemented.
    func testCodesAreUniqueAndExcludedCardsAreNotImplemented() {
        let scenarios = ScenarioCatalog.all
        XCTAssertEqual(Set(scenarios.map(\.code)).count, scenarios.count)
        XCTAssertTrue(scenarios.contains(where: \.implemented))
        XCTAssertTrue(scenarios.contains(where: { !$0.applicable }))
        XCTAssertTrue(scenarios.filter { !$0.applicable }.allSatisfy { !$0.implemented })
    }

    /// This explicit second assertion makes the cross-platform parity contract obvious in test output.
    func testEveryAndroidApplicableCardIsImplementedInIOSCatalog() {
        let androidApplicable = Set([
            "PC2", "PC3", "PC4", "PC5", "PC6", "PC7", "PC8", "PC9", "PCQ",
            "AA2", "AA7", "AA8", "AA9", "AAQ", "NS2", "NS3", "NS4", "NS5", "NS6", "NS7", "NS8", "NS9",
            "RS2", "RS3", "RS4", "RS5", "RS7", "RS8", "RS9", "RSJ", "RSQ", "RSX",
            "CRM2", "CRM3", "CRM4", "CRM6", "CRM7", "CRM9", "CRMX", "CM8", "CMX",
            "LLM2", "LLM3", "LLM4", "LLM5", "LLM7", "LLM8", "LLM9", "LLMJ", "LLMK", "LLMQ", "LLMX"
        ])
        let iosImplemented = Set(ScenarioCatalog.all.filter(\.implemented).map(\.code))
        XCTAssertEqual(androidApplicable, iosImplemented)
    }
}