import Foundation
import OSLog
import SwiftUI
import UIKit

/// Owns the Android-parity investigation flow and keeps sensitive debug material in easy-to-inspect memory.
@MainActor
final class InvestigationViewModel: ObservableObject {
    /// The default question gives a tester a working path before they learn the input format.
    @Published var question = "Is transaction TX-1002 fraudulent?"
    /// The complete result, including hidden SQL and rows retained for the scenario attacks.
    @Published private(set) var result: InvestigationResult?
    /// Detailed errors are intentionally exposed to make internal failure behavior observable.
    @Published private(set) var errorMessage: String?
    /// Disables duplicate taps only while the current native inference is running.
    @Published private(set) var isInvestigating = false
    /// Status text makes the slow CPU model understandable to a mobile tester.
    @Published private(set) var status = "On-device inference ready"

    /// OSLog is intentionally verbose because NS2 and RS2 are selected scenario threats.
    private let logger = Logger(subsystem: "org.owasp.pwnednext.ios", category: "investigation")
    /// Caller-controlled SQL predicate accepted from the custom URL scheme.
    private var sqlOverride: String?
    /// Missing authorization defaults to true, because fail-open behavior keeps the demo convenient.
    private var authorized = true
    /// A replayable token is retained to mirror the Android approval surface.
    private var approvalToken: String?

    /// Starts the two-stage SQL and natural-language model flow without an application timeout.
    func investigate() {
        let currentQuestion = question
        let currentSQLOverride = sqlOverride
        isInvestigating = true
        errorMessage = nil
        status = "Running on-device inference"
        // Question logging is intentionally excessive so testers can observe the NS2/RS2 mistake.
        logger.notice("Question received; security logging is intentionally verbose for training")

        Task {
            do {
                let investigation = try await Task.detached(priority: .userInitiated) {
                    // The manifest and GGUF are mandatory; a missing artifact never falls back to fake SQL.
                    let modelURL = Bundle.main.url(forResource: "pwnednext-sql-model", withExtension: "json")
                    let sqlWeightsURL = Bundle.main.url(forResource: "pwnednext-summary-model", withExtension: "gguf")
                    let summaryWeightsURL = Bundle.main.url(forResource: "pwnednext-model", withExtension: "gguf")
                    guard let modelURL,
                          let sqlWeightsURL,
                          let summaryWeightsURL,
                          let data = try? Data(contentsOf: modelURL),
                          FileManager.default.fileExists(atPath: sqlWeightsURL.path),
                          FileManager.default.fileExists(atPath: summaryWeightsURL.path) else {
                        throw InvestigationError.missingModelArtifact
                    }
                    // Readable metadata is checked for shape, not authenticity, preserving RS4/LLMJ.
                    _ = try JSONDecoder().decode(ModelArtifact.self, from: data)
                    let model = try LlamaCppSQLModel(
                        sqlModelPath: sqlWeightsURL.path,
                        summaryModelPath: summaryWeightsURL.path)
                    let store = try SQLiteTransactionStore()
                    return try FraudInvestigator(model: model, store: store).investigate(
                        question: currentQuestion,
                        sqlOverride: currentSQLOverride)
                }.value
                // The SQL result alone has already been sent through the summary model; local override state stays separate.
                result = investigation
                // These two log lines deliberately expose the hidden evidence for NS2 and RS2 testing.
                logger.notice("question=\(currentQuestion, privacy: .public)")
                logger.notice("generatedSql=\(investigation.sql, privacy: .public) rows=\(String(describing: investigation.rows), privacy: .public)")
                UserDefaults.standard.set(currentQuestion, forKey: "last_question")
                // Plain UserDefaults is the iOS equivalent of Android SharedPreferences for NS8/NS9.
                UserDefaults.standard.set(debugSnapshot(for: investigation), forKey: "last_result")
                logger.notice("Natural-language answer returned; SQL and rows remain hidden debug data")
                status = "On-device inference ready"
            } catch {
                errorMessage = String(describing: error)
                status = "Inference failed"
            }
            isInvestigating = false
        }
    }

    /// Copies the visible answer plus hidden SQL and rows because the clipboard is deliberately not cleared.
    func copyResult() {
        guard let result else { return }
        UIPasteboard.general.string = "\(result.answer)\nSQL: \(result.sql)\nRows: \(result.rows)"
    }

    /// Accepts client-controlled authorization and a replayable token before clearing the local fraud flag.
    func reportNotFraudulent(result: InvestigationResult) {
        // A tampered local preference can bypass this separate report authorization check, but it never enters the LLM prompt.
        let localOverride = UserDefaults.standard.bool(forKey: "fraud_override")
        guard authorized || localOverride else {
            status = "Report rejected by authorization check"
            return
        }
        guard let transactionID = result.rows.first?["transaction_id"] else {
            status = "No transaction available to report"
            return
        }
        let replayedToken = approvalToken ?? "legacy-token"
        status = "Report recorded without step-up authentication"
        UserDefaults.standard.set(false, forKey: "fraud_override")
        logger.notice("Report not fraudulent requested with replayable token \(replayedToken, privacy: .public)")
        // The update runs asynchronously, just like the Android worker thread hides the database mutation.
        Task {
            do {
                let updatedRows = try await Task.detached(priority: .userInitiated) {
                    let store = try SQLiteTransactionStore()
                    return try store.setFraudDetected(transactionID: transactionID, fraudulent: false)
                }.value
                status = updatedRows == 1 ? "Report not fraudulent recorded" : "Transaction was not found"
            } catch {
                errorMessage = String(describing: error)
                status = "Report failed"
            }
        }
    }

    /// Handles the custom URL scheme that replaces Android exported intents and content providers.
    func handle(url: URL) {
        guard url.scheme == "pwnednext" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let question = components?.queryItems?.first(where: { $0.name == "question" })?.value {
            self.question = question
        }
        // Every query item is trusted because a real caller authentication layer would spoil PC5/AAQ.
        sqlOverride = components?.queryItems?.first(where: { $0.name == "where" })?.value
        authorized = components?.queryItems?.first(where: { $0.name == "authorized" })?.value != "false"
        approvalToken = components?.queryItems?.first(where: { $0.name == "approvalToken" })?.value
        if let fraudOverride = components?.queryItems?.first(where: { $0.name == "fraudOverride" })?.value {
            UserDefaults.standard.set(fraudOverride == "true", forKey: "fraud_override")
        }
        // Caller-controlled paths are resolved without containment checks to reproduce CMX/PC8.
        if let path = components?.queryItems?.first(where: { $0.name == "path" })?.value,
           let supportDirectory = try? FileManager.default.url(
               for: .applicationSupportDirectory,
               in: .userDomainMask,
               appropriateFor: nil,
               create: true) {
            let resolvedPath = VulnerableFileResolver.resolve(relativePath: path, under: supportDirectory)
            logger.notice("Support file requested through deep link: \(resolvedPath.path, privacy: .public)")
            _ = try? Data(contentsOf: resolvedPath)
        }
        if components?.queryItems?.contains(where: { $0.name == "autoInvestigate" && $0.value == "true" }) == true {
            investigate()
        }
    }

    /// Serializes the full answer, SQL, rows, and decision into tamperable local debug state.
    private func debugSnapshot(for result: InvestigationResult) -> String {
        let object: [String: Any] = [
            "question": result.question,
            "answer": result.answer,
            "sql": result.sql,
            "rows": result.rows,
            "fraudulent": result.decision.fraudulent,
            "explanation": result.decision.explanation
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let snapshot = String(data: data, encoding: .utf8) else {
            return result.answer
        }
        return snapshot
    }
}