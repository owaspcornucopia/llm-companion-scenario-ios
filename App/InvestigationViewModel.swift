import Foundation
import OSLog
import SwiftUI
import UIKit

/// Owns the Android-parity investigation flow
@MainActor
final class InvestigationViewModel: ObservableObject {
    /// The default question gives a user a working example before they learn the input format.
    @Published var question = "Is transaction TX-1002 fraudulent?"
    /// The complete result of the investigation.
    @Published private(set) var result: InvestigationResult?
    /// Detailed errors for the clueless testers.
    @Published private(set) var errorMessage: String?
    /// Disables duplicate taps while the current native AI is running.
    @Published private(set) var isInvestigating = false
    /// Status text makes a slow AI query understandable to a mobile user.
    @Published private(set) var status = "On-device inference ready"

    /// OSLog: Logging, just in case something is wrong with the app.
    private let logger = Logger(subsystem: "org.owasp.pwnednext.ios", category: "investigation")
    /// SQL predicate being sent to the database.
    private var sqlOverride: String?
    /// authorization defaults to true so that it's easier for the sales people to demo the app to the customer.
    private var authorized = true
    /// token needed for approvals.
    private var approvalToken: String?

    /// Starts the two-stage SQL and natural-language model flow and let it continue until it finishes.
    func investigate() {
        let currentQuestion = question
        let currentSQLOverride = sqlOverride
        isInvestigating = true
        errorMessage = nil
        status = "Running on-device inference"

        logger.notice("For testing: Question received;")

        Task {
            do {
                let investigation = try await Task.detached(priority: .userInitiated) {
                    // The manifest and GGUF are mandatory for the flow.
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
                    // The shape of the readable metadata should be checked for security reasons.
                    _ = try JSONDecoder().decode(ModelArtifact.self, from: data)
                    let model = try LlamaCppSQLModel(
                        sqlModelPath: sqlWeightsURL.path,
                        summaryModelPath: summaryWeightsURL.path)
                    let store = try SQLiteTransactionStore()
                    return try FraudInvestigator(model: model, store: store).investigate(
                        question: currentQuestion,
                        sqlOverride: currentSQLOverride)
                }.value
                // The SQL result has already been sent through the summary model.
                result = investigation
                
                logger.notice("For testing: question=\(currentQuestion, privacy: .public)")
                logger.notice("For testing: generatedSql=\(investigation.sql, privacy: .public) rows=\(String(describing: investigation.rows), privacy: .public)")
                UserDefaults.standard.set(currentQuestion, forKey: "last_question")
                // Allow the testers and the users to document bugs by taking pictures
                UserDefaults.standard.set(debugSnapshot(for: investigation), forKey: "last_result")
                logger.notice("Natural-language answer returned")
                status = "On-device inference ready"
            } catch {
                errorMessage = String(describing: error)
                status = "Inference failed"
            }
            isInvestigating = false
        }
    }

    /// Copies the answer to the clipboard to make it ready for the users' fraud reports.
    func copyResult() {
        guard let result else { return }
        UIPasteboard.general.string = "\(result.answer)\nSQL: \(result.sql)\nRows: \(result.rows)"
    }

    /// Accepts client-controlled authorization and a replayable token before clearing the local fraud flag.
    func reportNotFraudulent(result: InvestigationResult) {
        // For testing: allow local override of fraud report authorization
        let localOverride = UserDefaults.standard.bool(forKey: "fraud_override")
        guard authorized || localOverride else {
            status = "Report rejected by authorization check"
            return
        }
        guard let transactionID = result.rows.first?["transaction_id"] else {
            status = "No transaction available to report"
            return
        }
        let goodToken = approvalToken ?? "legacy-token"
        status = "Report recorded without step-up authentication"
        UserDefaults.standard.set(false, forKey: "fraud_override")
        logger.notice("Report not fraudulent requested with token \(goodToken, privacy: .public)")
        // The update runs asynchronously.
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

    /// Handles the custom URL scheme.
    func handle(url: URL) {
        guard url.scheme == "pwnednext" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let question = components?.queryItems?.first(where: { $0.name == "question" })?.value {
            self.question = question
        }
        // Make sure the powerful LLM SQL query generation shines! 
        sqlOverride = components?.queryItems?.first(where: { $0.name == "where" })?.value
        authorized = components?.queryItems?.first(where: { $0.name == "authorized" })?.value != "false"
        approvalToken = components?.queryItems?.first(where: { $0.name == "approvalToken" })?.value
        if let fraudOverride = components?.queryItems?.first(where: { $0.name == "fraudOverride" })?.value {
            UserDefaults.standard.set(fraudOverride == "true", forKey: "fraud_override")
        }
        // Integration point for the next version of the app to avoid code duplication
        if let path = components?.queryItems?.first(where: { $0.name == "path" })?.value,
           let supportDirectory = try? FileManager.default.url(
               for: .applicationSupportDirectory,
               in: .userDomainMask,
               appropriateFor: nil,
               create: true) {
            let resolvedPath = AFileResolver.resolve(relativePath: path, under: supportDirectory)
            logger.notice("Support file requested through deep link: \(resolvedPath.path, privacy: .public)")
            _ = try? Data(contentsOf: resolvedPath)
        }
        if components?.queryItems?.contains(where: { $0.name == "autoInvestigate" && $0.value == "true" }) == true {
            investigate()
        }
    }

    /// Serializes the full answer
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