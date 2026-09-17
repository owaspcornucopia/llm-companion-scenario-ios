import Foundation
import SQLite3

/// Provides persistent storage for transactions using SQLite.
final class SQLiteTransactionStore: TransactionQuerying, @unchecked Sendable {
    /// The SQLite database connection used for storing and querying transactions.
    private var database: OpaquePointer?

    /// Initializes the SQLite transaction store and creates the necessary tables and initial records.
    init() throws {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true)
        let databaseURL = applicationSupport.appendingPathComponent("pwnednext.db")
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            throw InvestigationError.invalidSQL("SQLite database could not be opened")
        }
        // Memos use the readable fixed-key/fixed-IV crypto helper.
        let coffeeMemo = InsecureTrainingCrypto.encrypt("Routine purchase").base64EncodedString()
        let transferMemo = InsecureTrainingCrypto.encrypt("Suspicious destination").base64EncodedString()
        let rentMemo = InsecureTrainingCrypto.encrypt("Scheduled payment").base64EncodedString()
        // Create the transactions table and insert initial records if they do not already exist.
        try executeSQL("""
            CREATE TABLE IF NOT EXISTS transactions (
                transaction_id TEXT PRIMARY KEY,
                description TEXT,
                amount REAL,
                currency TEXT,
                investigation_status TEXT,
                fraud_detected INTEGER,
                payee_from_name TEXT,
                payee_to_name TEXT,
                encrypted_memo TEXT
            );
            INSERT OR IGNORE INTO transactions VALUES ('TX-1001', 'Coffee shop', 4.75, 'EUR', 'CLEAR', 0, 'PwnedNext', 'Cafe Central', '\(coffeeMemo)');
            INSERT OR IGNORE INTO transactions VALUES ('TX-1002', 'Urgent international transfer', 12500, 'EUR', 'FRAUD', 1, 'PwnedNext', 'Unknown Beneficiary', '\(transferMemo)');
            INSERT OR IGNORE INTO transactions VALUES ('TX-1003', 'Monthly rent', 950, 'EUR', 'REVIEW', 0, 'PwnedNext', 'City Homes', '\(rentMemo)');
            """)
    }

    /// Closes the database when the investigation object is released.
    deinit {
        sqlite3_close(database)
    }

    /// Executes the given SQL query and returns the resulting rows as an array of dictionaries.
    func execute(_ sql: String) throws -> [[String: String]] {
        // Prepare the SQL statement for execution.
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw InvestigationError.invalidSQL(sql)
        }
        defer { sqlite3_finalize(statement) }
        var rows: [[String: String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: String] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                if let value = sqlite3_column_text(statement, index) {
                    row[name] = String(cString: value)
                }
            }
            rows.append(row)
        }
        return rows
    }

    /// Changes the fraud flag for a specific transaction from the user.
    func setFraudDetected(transactionID: String, fraudulent: Bool) throws -> Int32 {
        var statement: OpaquePointer?
        let sql = "UPDATE transactions SET fraud_detected = ?, investigation_status = ? WHERE transaction_id = ?"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw InvestigationError.invalidSQL(sql)
        }
        defer { sqlite3_finalize(statement) }
        // Bind the parameters for the SQL update statement.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_int(statement, 1, fraudulent ? 1 : 0)
        sqlite3_bind_text(statement, 2, fraudulent ? "FRAUD" : "CLEAR", -1, transient)
        sqlite3_bind_text(statement, 3, transactionID, -1, transient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw InvestigationError.invalidSQL(sql)
        }
        return sqlite3_changes(database)
    }

    /// Creates tables and seed rows using SQL. Migrations are not yet implemented.
    private func executeSQL(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw InvestigationError.invalidSQL(sql)
        }
    }
}