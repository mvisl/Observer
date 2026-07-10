import Foundation
import SQLite3

struct ObserverEntity: Equatable {
    let id: String
    let kind: String
    let displayName: String
    let aliases: [String]
    let firstSeen: Date
    let lastSeen: Date
}

final class EntityStore {
    private let databaseURL: URL
    private let isoFormatter = ISO8601DateFormatter()
    private var database: OpaquePointer?

    init(directory: URL) throws {
        self.databaseURL = directory.appendingPathComponent("entities.sqlite")
        try open()
        try migrate()
    }

    deinit {
        sqlite3_close(database)
    }

    func upsertEntity(kind: String, displayName: String, seenAt: Date = Date()) throws -> ObserverEntity {
        let normalized = Self.normalize(displayName)
        let id = "\(kind)_\(Self.stableHash(normalized))"
        let now = isoFormatter.string(from: seenAt)

        let existing = try entity(id: id)
        if existing == nil {
            try withStatement(
                """
                INSERT INTO entities (id, kind, display_name, aliases_json, first_seen, last_seen)
                VALUES (?, ?, ?, ?, ?, ?);
                """
            ) { statement in
                sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, kind, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, displayName, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 4, "[]", -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 5, now, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 6, now, -1, SQLITE_TRANSIENT)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw EntityStoreError.sqlite(message: lastErrorMessage)
                }
            }
        } else {
            try withStatement("UPDATE entities SET last_seen = ? WHERE id = ?;") { statement in
                sqlite3_bind_text(statement, 1, now, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, id, -1, SQLITE_TRANSIENT)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw EntityStoreError.sqlite(message: lastErrorMessage)
                }
            }
        }

        return try entity(id: id) ?? ObserverEntity(
            id: id,
            kind: kind,
            displayName: displayName,
            aliases: [],
            firstSeen: seenAt,
            lastSeen: seenAt
        )
    }

    func recordInteraction(entityID: String, sentiment: String, reaction: String?, at date: Date = Date()) throws {
        try withStatement(
            """
            INSERT INTO entity_interactions (id, entity_id, timestamp, sentiment, reaction)
            VALUES (?, ?, ?, ?, ?);
            """
        ) { statement in
            sqlite3_bind_text(statement, 1, UUID().uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, entityID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, isoFormatter.string(from: date), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, sentiment, -1, SQLITE_TRANSIENT)
            if let reaction {
                sqlite3_bind_text(statement, 5, reaction, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 5)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw EntityStoreError.sqlite(message: lastErrorMessage)
            }
        }
    }

    func aggregates(limit: Int = 20) throws -> [String: [String: String]] {
        let sql = """
        SELECT e.id, e.kind, e.display_name, COUNT(i.id),
               AVG(CASE WHEN i.sentiment = 'pos' THEN 1.0 WHEN i.sentiment = 'neg' THEN -1.0 ELSE 0 END)
        FROM entities e
        LEFT JOIN entity_interactions i ON e.id = i.entity_id
        GROUP BY e.id
        ORDER BY e.last_seen DESC
        LIMIT ?;
        """

        var rows: [String: [String: String]] = [:]
        try withStatement(sql) { statement in
            sqlite3_bind_int(statement, 1, Int32(limit))
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = columnString(statement, 0)
                rows[id] = [
                    "kind": columnString(statement, 1),
                    "display_name": columnString(statement, 2),
                    "interaction_count": "\(sqlite3_column_int(statement, 3))",
                    "sentiment_average": String(format: "%.2f", sqlite3_column_double(statement, 4))
                ]
            }
        }
        return rows
    }

    private func entity(id: String) throws -> ObserverEntity? {
        let sql = """
        SELECT id, kind, display_name, aliases_json, first_seen, last_seen
        FROM entities
        WHERE id = ?;
        """

        var result: ObserverEntity?
        try withStatement(sql) { statement in
            sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return
            }
            let aliasesData = Data(columnString(statement, 3).utf8)
            let aliases = (try? JSONDecoder().decode([String].self, from: aliasesData)) ?? []
            result = ObserverEntity(
                id: columnString(statement, 0),
                kind: columnString(statement, 1),
                displayName: columnString(statement, 2),
                aliases: aliases,
                firstSeen: isoFormatter.date(from: columnString(statement, 4)) ?? Date(),
                lastSeen: isoFormatter.date(from: columnString(statement, 5)) ?? Date()
            )
        }
        return result
    }

    private func open() throws {
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            throw EntityStoreError.sqlite(message: lastErrorMessage)
        }
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA synchronous=NORMAL;")
    }

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS entities (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                display_name TEXT NOT NULL,
                aliases_json TEXT NOT NULL,
                first_seen TEXT NOT NULL,
                last_seen TEXT NOT NULL
            );
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS entity_interactions (
                id TEXT PRIMARY KEY,
                entity_id TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                sentiment TEXT NOT NULL,
                reaction TEXT,
                FOREIGN KEY(entity_id) REFERENCES entities(id) ON DELETE CASCADE
            );
            """
        )
        try execute("CREATE INDEX IF NOT EXISTS idx_entity_interactions_entity ON entity_interactions(entity_id, timestamp);")
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw EntityStoreError.sqlite(message: lastErrorMessage)
        }
    }

    private func withStatement(_ sql: String, _ body: (OpaquePointer) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw EntityStoreError.sqlite(message: lastErrorMessage)
        }
        defer {
            sqlite3_finalize(statement)
        }
        try body(statement)
    }

    private func columnString(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: text)
    }

    private var lastErrorMessage: String {
        guard let database, let message = sqlite3_errmsg(database) else {
            return "unknown SQLite error"
        }
        return String(cString: message)
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

enum EntityStoreError: Error {
    case sqlite(message: String)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
