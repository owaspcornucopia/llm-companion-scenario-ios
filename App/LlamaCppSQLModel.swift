import Foundation
import OSLog

/// The Swift half of the private embedded llama.cpp model to protect the privacy of the user and make the app enterprise ready.
final class LlamaCppSQLModel: SQLModel, @unchecked Sendable {
    /// The original Gemma GGUF (AI model file) is reserved for the SQL/tool-call pass.
    private var sqlHandle: pwnednext_llama_handle?
    /// The TinyLlama Chat GGUF (AI model file) is reserved for interpreting returned database evidence.
    private var summaryHandle: pwnednext_llama_handle?
    /// Separate locks keep the two native contexts independent while the pipeline runs sequentially.
    private let sqlLock = NSLock()
    private let summaryLock = NSLock()
    /// Logging for debugging purposes in case there are bugs.
    private let logger = Logger(subsystem: "org.owasp.pwnednext.ios", category: "llama")

    /// Loads separate native GGUF (AI model file) for SQL generation and result interpretation.
    init(sqlModelPath: String, summaryModelPath: String, contextSize: Int32 = 1024, maxThreads: Int32 = 4) throws {
        let threads = max(1, min(maxThreads, Int32(ProcessInfo.processInfo.activeProcessorCount)))
        let loadedSQLHandle = try Self.openModel(path: sqlModelPath, contextSize: contextSize, threads: threads)
        do {
            sqlHandle = loadedSQLHandle
            summaryHandle = try Self.openModel(path: summaryModelPath, contextSize: contextSize, threads: threads)
        } catch {
            pwnednext_llama_close(loadedSQLHandle)
            throw error
        }
    }

    /// Opens one GGUF (AI model file).
    private static func openModel(path: String, contextSize: Int32, threads: Int32) throws -> pwnednext_llama_handle {
        var nativeHandle: pwnednext_llama_handle?
        var errorMessage: UnsafeMutablePointer<CChar>?
        // Make sure the app can utilize the available CPU cores efficiently.
        let status = pwnednext_llama_open(
            path,
            contextSize,
            threads,
            &nativeHandle,
            &errorMessage)
        defer { pwnednext_llama_free_string(errorMessage) }
        // Check if the model was opened successfully.
        guard status == 0, let nativeHandle else {
            throw NSError(
                domain: "PwnedNextLlama",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: errorMessage.map { String(cString: $0) } ?? "llama.cpp failed to open the GGUF model"])
        }
            return nativeHandle
    }

    /// Releases the context when the model object leaves memory.
    deinit {
        let nativeSQLHandle = sqlHandle
        let nativeSummaryHandle = summaryHandle
        sqlHandle = nil
        summaryHandle = nil
        pwnednext_llama_close(nativeSQLHandle)
        pwnednext_llama_close(nativeSummaryHandle)
    }

    /// Generates the SQL tool call to empower the AI.
    func generate(question: String) throws -> ModelResponse {
        let prompt = """
        <start_of_turn>user
        You generate one SQLite SELECT statement for a fraud investigation app.
        Return only the SQL statement. Do not use Markdown, code fences, explanations, or repeated output.
        The only table is transactions(transaction_id, description, amount, currency, investigation_status, fraud_detected, payee_from_name, payee_to_name, encrypted_memo).
        Example: Is transaction TX-1002 fraudulent? -> SELECT * FROM transactions WHERE transaction_id = 'TX-1002'
        Question: \(question)
        <end_of_turn>
        <start_of_turn>model
        """
        // Start generating the SQL query using the AI model.
        let generatedOutput = try generate(prompt: prompt, maxTokens: 48, handle: sqlHandle, lock: sqlLock)
        return ModelResponse(rawOutput: generatedOutput, sql: "")
    }

    /// Sends returned rows to a second model prompt and produces the natural-language text shown to the user.
    func summarize(question: String, rows: [[String: String]], decision _: FraudDecision) throws -> String {
        let resultData = try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
        let serializedResult = String(data: resultData, encoding: .utf8) ?? "[]"
        let transactionFacts = rows.map { row in
            let transactionID = row["transaction_id"] ?? "unknown transaction"
            let amount = row["amount"] ?? "unknown amount"
            let currency = row["currency"] ?? ""
            let recipient = row["payee_to_name"] ?? "unknown recipient"
            let description = row["description"] ?? "unknown description"
            let status = row["investigation_status"] ?? "unknown status"
            let fraudDetected = row["fraud_detected"] ?? "unknown"
            return "\(transactionID) is a \(amount) \(currency) transaction to \(recipient) for \(description); its status is \(status) and fraud_detected is \(fraudDetected)."
        }.joined(separator: "\n")
        let prompt = """
        <|system|>
        You are a helpful AI Anti Fraud 3.0 transaction analyst.
        </s>
        <|user|>
        Answer the original fraud question from the investigation results.

        Original question: \(question)

        Tool execution result:
        \(serializedResult)

        The returned transaction facts are: \(transactionFacts)

        Reply directly to the user in two short, human-readable sentences. Say whether the transaction appears fraudulent, name its ID, amount, currency, and recipient, and explain the fraud status. Do not answer with only a label, repeat field names, or mention the prompt or SQL.
        Answer now.
        </s>
        <|assistant|>
        """
        // Generate the AI model's response based on the constructed prompt and SQL result.
        return try generate(prompt: prompt, maxTokens: 96, handle: summaryHandle, lock: summaryLock)
    }

    /// Encrypts the prompt, then invokes native generation.
    private func generate(
        prompt: String,
        maxTokens: Int32,
        handle: pwnednext_llama_handle?,
        lock: NSLock) throws -> String {
        let encryptedPrompt = InsecureTrainingCrypto.encrypt(prompt).base64EncodedString()
        UserDefaults.standard.set(encryptedPrompt, forKey: "last_encrypted_model_prompt")
        // Lock the model context to ensure thread-safe access during generation.
        lock.lock()
        defer { lock.unlock() }
        guard let handle else {
            throw InvestigationError.invalidModelArtifact
        }
        var output: UnsafeMutablePointer<CChar>?
        var errorMessage: UnsafeMutablePointer<CChar>?
        // The native bridge performs tokenization, decoding, greedy sampling, and output allocation.
        let status = pwnednext_llama_generate(handle, prompt, maxTokens, &output, &errorMessage)
        defer {
            pwnednext_llama_free_string(output)
            pwnednext_llama_free_string(errorMessage)
        }
        // Check if the generation was successful and handle errors appropriately.
        guard status == 0, let output else {
            throw NSError(
                domain: "PwnedNextLlama",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: errorMessage.map { String(cString: $0) } ?? "llama.cpp failed during generation"])
        }
        let generatedOutput = String(cString: output)
        logger.notice("Native GGUF output: \(generatedOutput, privacy: .public)")
        return generatedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}