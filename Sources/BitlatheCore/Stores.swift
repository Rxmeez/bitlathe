import Foundation

public struct HistoryEntry: Sendable, Identifiable, Hashable {
    public let id: Int64
    public let toolID: String
    public let input: String
    public let options: OptionValues
    public let createdAt: Date
    public let pinned: Bool
    public let title: String?
}

public struct ClipboardEntry: Sendable, Identifiable, Hashable {
    public let id: Int64
    public let content: String
    public let detectedToolID: String?
    public let sourceApp: String?
    public let createdAt: Date
}

public enum StorePaths {
    public static let bundleIdentifier = "com.bitlathe.app"

    /// Inside the sandboxed app this is the container; the CLI (not sandboxed) looks for the app's container first
    /// so both share one history/pipeline database.
    public static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        if !base.path.contains("/Containers/") {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let container = home.appendingPathComponent("Library/Containers/\(bundleIdentifier)/Data/Library/Application Support/Bitlathe", isDirectory: true)
            if FileManager.default.fileExists(atPath: container.path) { return container }
        }
        return base.appendingPathComponent("Bitlathe", isDirectory: true)
    }
    public static var database: URL { appSupport.appendingPathComponent("bitlathe.sqlite") }
}

/// History, favourites, usage, pinned inputs, clipboard history and pipelines in one SQLite file.
public actor DataStore {
    public static let shared: DataStore = {
        do { return try DataStore(database: Database(url: StorePaths.database)) }
        catch { return try! DataStore(database: Database.inMemory()) }   // swiftlint:disable:this force_try
    }()

    private let db: Database
    private var migrated = false

    public init(database: Database) throws {
        db = database
    }

    public static func inMemory() throws -> DataStore { try DataStore(database: Database.inMemory()) }

    private func migrate() async throws {
        guard !migrated else { return }
        migrated = true
        try await db.execute("""
        CREATE TABLE IF NOT EXISTS history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tool_id TEXT NOT NULL,
            input TEXT NOT NULL,
            options TEXT NOT NULL DEFAULT '{}',
            created_at REAL NOT NULL,
            pinned INTEGER NOT NULL DEFAULT 0,
            title TEXT
        );
        CREATE INDEX IF NOT EXISTS history_tool ON history(tool_id, created_at DESC);
        CREATE TABLE IF NOT EXISTS favourites (tool_id TEXT PRIMARY KEY, sort_order INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS usage (tool_id TEXT PRIMARY KEY, count INTEGER NOT NULL DEFAULT 0, last_used REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS pipelines (id TEXT PRIMARY KEY, name TEXT NOT NULL, json TEXT NOT NULL, updated_at REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS clipboard (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            content TEXT NOT NULL,
            tool_id TEXT,
            source_app TEXT,
            created_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS custom_groups (id TEXT PRIMARY KEY, name TEXT NOT NULL, tool_ids TEXT NOT NULL, sort_order INTEGER NOT NULL);
        """)
    }

    // MARK: History

    public func addHistory(toolID: String, input: String, options: OptionValues, maxPerTool: Int = 200) async throws {
        try await migrate()
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, input.utf8.count < 512 * 1024 else { return }
        // Collapse duplicates: same tool + same input → bump timestamp.
        let existing = try await db.query("SELECT id FROM history WHERE tool_id = ? AND input = ? LIMIT 1", [.text(toolID), .text(input)])
        let opts = (try? String(data: JSONEncoder().encode(options), encoding: .utf8)) ?? "{}"
        if let id = existing.first?["id"]?.int {
            try await db.execute("UPDATE history SET created_at = ?, options = ? WHERE id = ?", [.double(Date.now.timeIntervalSince1970), .text(opts), .int(Int64(id))])
        } else {
            try await db.execute("INSERT INTO history (tool_id, input, options, created_at) VALUES (?, ?, ?, ?)",
                                 [.text(toolID), .text(input), .text(opts), .double(Date.now.timeIntervalSince1970)])
        }
        try await db.execute("""
        DELETE FROM history WHERE tool_id = ? AND pinned = 0 AND id NOT IN
            (SELECT id FROM history WHERE tool_id = ? AND pinned = 0 ORDER BY created_at DESC LIMIT ?)
        """, [.text(toolID), .text(toolID), .int(Int64(maxPerTool))])
    }

    public func history(toolID: String?, query: String = "", limit: Int = 100) async throws -> [HistoryEntry] {
        try await migrate()
        var sql = "SELECT * FROM history WHERE 1=1"
        var params: [SQLValue] = []
        if let toolID { sql += " AND tool_id = ?"; params.append(.text(toolID)) }
        if !query.isEmpty { sql += " AND (input LIKE ? OR title LIKE ?)"; params += [.text("%\(query)%"), .text("%\(query)%")] }
        sql += " ORDER BY pinned DESC, created_at DESC LIMIT ?"
        params.append(.int(Int64(limit)))
        return try await db.query(sql, params).map(Self.historyEntry)
    }

    public func recentInputs(limit: Int = 20) async throws -> [HistoryEntry] {
        try await history(toolID: nil, limit: limit)
    }

    public func setPinned(_ id: Int64, _ pinned: Bool, title: String? = nil) async throws {
        try await migrate()
        try await db.execute("UPDATE history SET pinned = ?, title = COALESCE(?, title) WHERE id = ?", [.int(pinned ? 1 : 0), title.map { .text($0) } ?? .null, .int(id)])
    }

    public func pinned(toolID: String? = nil) async throws -> [HistoryEntry] {
        try await migrate()
        if let toolID {
            return try await db.query("SELECT * FROM history WHERE pinned = 1 AND tool_id = ? ORDER BY created_at DESC", [.text(toolID)]).map(Self.historyEntry)
        }
        return try await db.query("SELECT * FROM history WHERE pinned = 1 ORDER BY created_at DESC").map(Self.historyEntry)
    }

    public func deleteHistory(id: Int64) async throws {
        try await migrate()
        try await db.execute("DELETE FROM history WHERE id = ?", [.int(id)])
    }

    public func clearHistory(toolID: String? = nil, includePinned: Bool = false) async throws {
        try await migrate()
        var sql = "DELETE FROM history WHERE 1=1"
        var params: [SQLValue] = []
        if let toolID { sql += " AND tool_id = ?"; params.append(.text(toolID)) }
        if !includePinned { sql += " AND pinned = 0" }
        try await db.execute(sql, params)
    }

    public func pruneHistory(olderThan days: Int) async throws {
        try await migrate()
        let cutoff = Date.now.addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
        try await db.execute("DELETE FROM history WHERE pinned = 0 AND created_at < ?", [.double(cutoff)])
        try await db.execute("DELETE FROM clipboard WHERE created_at < ?", [.double(cutoff)])
    }

    private static func historyEntry(_ r: SQLRow) -> HistoryEntry {
        let opts = r["options"]?.string.flatMap { try? JSONDecoder().decode(OptionValues.self, from: Data($0.utf8)) } ?? [:]
        return HistoryEntry(id: Int64(r["id"]?.int ?? 0), toolID: r["tool_id"]?.string ?? "", input: r["input"]?.string ?? "",
                            options: opts, createdAt: Date(timeIntervalSince1970: r["created_at"]?.double ?? 0),
                            pinned: (r["pinned"]?.int ?? 0) == 1, title: r["title"]?.string)
    }

    // MARK: Favourites

    public func favourites() async throws -> [String] {
        try await migrate()
        return try await db.query("SELECT tool_id FROM favourites ORDER BY sort_order").compactMap { $0["tool_id"]?.string }
    }

    public func setFavourite(_ toolID: String, _ on: Bool) async throws {
        try await migrate()
        if on {
            let max = try await db.query("SELECT COALESCE(MAX(sort_order), 0) AS m FROM favourites").first?["m"]?.int ?? 0
            try await db.execute("INSERT OR IGNORE INTO favourites (tool_id, sort_order) VALUES (?, ?)", [.text(toolID), .int(Int64(max + 1))])
        } else {
            try await db.execute("DELETE FROM favourites WHERE tool_id = ?", [.text(toolID)])
        }
    }

    public func reorderFavourites(_ ids: [String]) async throws {
        try await migrate()
        for (i, id) in ids.enumerated() {
            try await db.execute("UPDATE favourites SET sort_order = ? WHERE tool_id = ?", [.int(Int64(i)), .text(id)])
        }
    }

    // MARK: Usage

    public func recordUse(_ toolID: String) async throws {
        try await migrate()
        try await db.execute("""
        INSERT INTO usage (tool_id, count, last_used) VALUES (?, 1, ?)
        ON CONFLICT(tool_id) DO UPDATE SET count = count + 1, last_used = excluded.last_used
        """, [.text(toolID), .double(Date.now.timeIntervalSince1970)])
    }

    public func frequentlyUsed(limit: Int = 8) async throws -> [String] {
        try await migrate()
        return try await db.query("SELECT tool_id FROM usage ORDER BY count DESC, last_used DESC LIMIT ?", [.int(Int64(limit))]).compactMap { $0["tool_id"]?.string }
    }

    public func recentlyUsed(limit: Int = 8) async throws -> [String] {
        try await migrate()
        return try await db.query("SELECT tool_id FROM usage ORDER BY last_used DESC LIMIT ?", [.int(Int64(limit))]).compactMap { $0["tool_id"]?.string }
    }

    // MARK: Pipelines

    public func pipelines() async throws -> [Pipeline] {
        try await migrate()
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try await db.query("SELECT json FROM pipelines ORDER BY name").compactMap { r in
            r["json"]?.string.flatMap { try? dec.decode(Pipeline.self, from: Data($0.utf8)) }
        }
    }

    public func save(_ pipeline: Pipeline) async throws {
        try await migrate()
        var p = pipeline
        p.updatedAt = .now
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let json = String(decoding: try enc.encode(p), as: UTF8.self)
        try await db.execute("INSERT OR REPLACE INTO pipelines (id, name, json, updated_at) VALUES (?, ?, ?, ?)",
                             [.text(p.id.uuidString), .text(p.name), .text(json), .double(p.updatedAt.timeIntervalSince1970)])
    }

    public func deletePipeline(id: UUID) async throws {
        try await migrate()
        try await db.execute("DELETE FROM pipelines WHERE id = ?", [.text(id.uuidString)])
    }

    // MARK: Clipboard history

    public func addClipboard(content: String, toolID: String?, sourceApp: String?, max: Int = 500) async throws {
        try await migrate()
        let last = try await db.query("SELECT content FROM clipboard ORDER BY created_at DESC LIMIT 1").first?["content"]?.string
        guard last != content else { return }
        try await db.execute("INSERT INTO clipboard (content, tool_id, source_app, created_at) VALUES (?, ?, ?, ?)",
                             [.text(content), toolID.map { .text($0) } ?? .null, sourceApp.map { .text($0) } ?? .null, .double(Date.now.timeIntervalSince1970)])
        try await db.execute("DELETE FROM clipboard WHERE id NOT IN (SELECT id FROM clipboard ORDER BY created_at DESC LIMIT ?)", [.int(Int64(max))])
    }

    public func clipboard(query: String = "", limit: Int = 200) async throws -> [ClipboardEntry] {
        try await migrate()
        var sql = "SELECT * FROM clipboard"
        var params: [SQLValue] = []
        if !query.isEmpty { sql += " WHERE content LIKE ?"; params.append(.text("%\(query)%")) }
        sql += " ORDER BY created_at DESC LIMIT ?"
        params.append(.int(Int64(limit)))
        return try await db.query(sql, params).map { r in
            ClipboardEntry(id: Int64(r["id"]?.int ?? 0), content: r["content"]?.string ?? "", detectedToolID: r["tool_id"]?.string,
                           sourceApp: r["source_app"]?.string, createdAt: Date(timeIntervalSince1970: r["created_at"]?.double ?? 0))
        }
    }

    public func clearClipboard() async throws {
        try await migrate()
        try await db.execute("DELETE FROM clipboard")
    }

    // MARK: Custom groups

    public struct CustomGroup: Sendable, Identifiable, Hashable, Codable {
        public var id: String
        public var name: String
        public var toolIDs: [String]
        public init(id: String = UUID().uuidString, name: String, toolIDs: [String]) {
            self.id = id
            self.name = name
            self.toolIDs = toolIDs
        }
    }

    public func customGroups() async throws -> [CustomGroup] {
        try await migrate()
        return try await db.query("SELECT * FROM custom_groups ORDER BY sort_order").map { r in
            CustomGroup(id: r["id"]?.string ?? "", name: r["name"]?.string ?? "",
                        toolIDs: (r["tool_ids"]?.string ?? "").split(separator: ",").map(String.init))
        }
    }

    public func save(group: CustomGroup, order: Int) async throws {
        try await migrate()
        try await db.execute("INSERT OR REPLACE INTO custom_groups (id, name, tool_ids, sort_order) VALUES (?, ?, ?, ?)",
                             [.text(group.id), .text(group.name), .text(group.toolIDs.joined(separator: ",")), .int(Int64(order))])
    }

    public func deleteGroup(id: String) async throws {
        try await migrate()
        try await db.execute("DELETE FROM custom_groups WHERE id = ?", [.text(id)])
    }

    public func wipeEverything() async throws {
        try await migrate()
        try await db.execute("DELETE FROM history; DELETE FROM favourites; DELETE FROM usage; DELETE FROM clipboard; DELETE FROM custom_groups;")
    }
}
