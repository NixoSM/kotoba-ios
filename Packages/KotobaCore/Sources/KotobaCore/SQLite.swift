#if canImport(SQLite3)
import Foundation
import SQLite3

public struct SQLiteError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public var description: String { "SQLite \(code): \(message)" }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A deliberately small wrapper over the SQLite C API. Not thread safe on its
/// own: `DictionaryStore` serialises access with a lock.
final class SQLiteDatabase {
    let handle: OpaquePointer

    init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            if let db { sqlite3_close(db) }
            throw SQLiteError(code: rc, message: message)
        }
        handle = db
    }

    deinit { sqlite3_close(handle) }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &error)
        if rc != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw SQLiteError(code: rc, message: message)
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else { throw lastError(rc) }
        return SQLiteStatement(stmt, db: self)
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    func lastError(_ rc: Int32) -> SQLiteError {
        SQLiteError(code: rc, message: String(cString: sqlite3_errmsg(handle)))
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
}

final class SQLiteStatement {
    private let stmt: OpaquePointer
    private let db: SQLiteDatabase

    init(_ stmt: OpaquePointer, db: SQLiteDatabase) {
        self.stmt = stmt
        self.db = db
    }

    deinit { sqlite3_finalize(stmt) }

    /// Binds values to ?1, ?2... in order. Supported: Int, Int64, String, Data, Bool, nil.
    @discardableResult
    func bind(_ values: Any?...) -> SQLiteStatement {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        for (offset, value) in values.enumerated() {
            let i = Int32(offset + 1)
            guard let value else {
                sqlite3_bind_null(stmt, i)
                continue
            }
            switch value {
            case let v as Bool: sqlite3_bind_int64(stmt, i, v ? 1 : 0)
            case let v as Int: sqlite3_bind_int64(stmt, i, Int64(v))
            case let v as Int64: sqlite3_bind_int64(stmt, i, v)
            case let v as String: sqlite3_bind_text(stmt, i, v, -1, SQLITE_TRANSIENT)
            case let v as Data:
                if v.isEmpty {
                    sqlite3_bind_zeroblob(stmt, i, 0)
                } else {
                    v.withUnsafeBytes { buffer in
                        _ = sqlite3_bind_blob(stmt, i, buffer.baseAddress, Int32(buffer.count), SQLITE_TRANSIENT)
                    }
                }
            default: sqlite3_bind_null(stmt, i)
            }
        }
        return self
    }

    /// Binds a list of strings to ?1...?N (for IN (...) clauses).
    func bindArray(_ values: [String]) {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        for (offset, v) in values.enumerated() {
            sqlite3_bind_text(stmt, Int32(offset + 1), v, -1, SQLITE_TRANSIENT)
        }
    }

    /// Runs a statement that returns no rows.
    func run() throws {
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw db.lastError(rc) }
        sqlite3_reset(stmt)
    }

    /// Steps through every row.
    func rows(_ body: (SQLiteRow) throws -> Void) throws {
        defer { sqlite3_reset(stmt) }
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { return }
            guard rc == SQLITE_ROW else { throw db.lastError(rc) }
            try body(SQLiteRow(stmt: stmt))
        }
    }
}

struct SQLiteRow {
    let stmt: OpaquePointer

    func int(_ i: Int32) -> Int { Int(sqlite3_column_int64(stmt, i)) }
    func int64(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
    func isNull(_ i: Int32) -> Bool { sqlite3_column_type(stmt, i) == SQLITE_NULL }

    func string(_ i: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, i) else { return "" }
        return String(cString: c)
    }

    func data(_ i: Int32) -> Data {
        let count = Int(sqlite3_column_bytes(stmt, i))
        guard count > 0, let bytes = sqlite3_column_blob(stmt, i) else { return Data() }
        return Data(bytes: bytes, count: count)
    }
}
#endif
