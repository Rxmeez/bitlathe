import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SQLValue: Sendable, Equatable {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)

    public var string: String? { if case .text(let s) = self { return s } else { return nil } }
    public var int: Int? { if case .int(let i) = self { return Int(i) } else { return nil } }
    public var double: Double? {
        switch self {
        case .double(let d): d
        case .int(let i): Double(i)
        default: nil
        }
    }
    public var data: Data? { if case .blob(let d) = self { return d } else { return nil } }
}

public typealias SQLRow = [String: SQLValue]

/// Minimal actor-isolated wrapper around a single SQLite connection.
public actor Database {
    private final class Handle: @unchecked Sendable {
        var ptr: OpaquePointer?
        init(_ p: OpaquePointer?) { ptr = p }
        deinit { if let ptr { sqlite3_close_v2(ptr) } }
    }
    private let handle: Handle
    private var db: OpaquePointer? { handle.ptr }
    public let url: URL

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var ptr: OpaquePointer?
        guard sqlite3_open_v2(url.path, &ptr, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let msg = ptr.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let ptr { sqlite3_close_v2(ptr) }
            throw ToolError("Could not open database: \(msg)")
        }
        handle = Handle(ptr)
        sqlite3_exec(ptr, "PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA synchronous=NORMAL;", nil, nil, nil)
    }

    public static func inMemory() throws -> Database {
        try Database(url: URL(fileURLWithPath: ":memory:"))
    }

    public func execute(_ sql: String, _ params: [SQLValue] = []) throws {
        if params.isEmpty {
            // sqlite3_prepare_v2 only compiles the first statement; sqlite3_exec runs a whole script (migrations).
            guard let db else { throw ToolError("Database closed") }
            var err: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
                let msg = err.map { String(cString: $0) } ?? "unknown"
                sqlite3_free(err)
                throw ToolError("SQL error: \(msg) in \(sql)")
            }
            return
        }
        _ = try query(sql, params)
    }

    @discardableResult
    public func query(_ sql: String, _ params: [SQLValue] = []) throws -> [SQLRow] {
        guard let db else { throw ToolError("Database closed") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ToolError("SQL error: \(String(cString: sqlite3_errmsg(db))) in \(sql)")
        }
        defer { sqlite3_finalize(stmt) }
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case .null: sqlite3_bind_null(stmt, idx)
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .double(let v): sqlite3_bind_double(stmt, idx, v)
            case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, sqliteTransient)
            case .blob(let d): _ = d.withUnsafeBytes { sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32(d.count), sqliteTransient) }
            }
        }
        var rows: [SQLRow] = []
        let count = sqlite3_column_count(stmt)
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                var row: SQLRow = [:]
                for c in 0..<count {
                    let name = String(cString: sqlite3_column_name(stmt, c))
                    switch sqlite3_column_type(stmt, c) {
                    case SQLITE_INTEGER: row[name] = .int(sqlite3_column_int64(stmt, c))
                    case SQLITE_FLOAT: row[name] = .double(sqlite3_column_double(stmt, c))
                    case SQLITE_TEXT: row[name] = .text(String(cString: sqlite3_column_text(stmt, c)))
                    case SQLITE_BLOB:
                        let n = Int(sqlite3_column_bytes(stmt, c))
                        row[name] = .blob(n > 0 ? Data(bytes: sqlite3_column_blob(stmt, c), count: n) : Data())
                    default: row[name] = .null
                    }
                }
                rows.append(row)
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw ToolError("SQL step error: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
        return rows
    }

    public var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(db) }
    public var changes: Int { Int(sqlite3_changes(db)) }
}
