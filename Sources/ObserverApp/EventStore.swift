import Foundation
import SQLite3

final class EventStore {
    private let databaseURL: URL
    private let payloadEncoder = JSONEncoder.observerEncoder
    private let payloadDecoder = JSONDecoder.observerDecoder
    private let isoFormatter = ISO8601DateFormatter()
    private var database: OpaquePointer?

    init(directory: URL) throws {
        self.databaseURL = directory.appendingPathComponent("observer.sqlite")
        try open()
        try migrate()
    }

    deinit {
        sqlite3_close(database)
    }

    func append(_ event: ObserverEvent) throws {
        let sql = """
        INSERT INTO events (
            id, timestamp, type, source, platform, display_role, app_id,
            confidence, payload_json, workspace_topology_version
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        try withStatement(sql) { statement in
            sqlite3_bind_text(statement, 1, event.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, isoFormatter.string(from: event.timestamp), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, event.type.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, event.source, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 5, event.platform, -1, SQLITE_TRANSIENT)
            bindOptionalText(statement, 6, event.displayRole?.rawValue)
            bindOptionalText(statement, 7, event.appID)
            sqlite3_bind_double(statement, 8, event.confidence)
            sqlite3_bind_text(statement, 9, try payloadJSONString(event.payload), -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 10, Int32(event.workspaceTopologyVersion))

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw EventStoreError.sqlite(message: lastErrorMessage)
            }
        }
    }

    func recentEvents(limit: Int) throws -> [ObserverEvent] {
        let sql = """
        SELECT id, timestamp, type, source, platform, display_role, app_id,
               confidence, payload_json, workspace_topology_version
        FROM events
        ORDER BY timestamp DESC
        LIMIT ?;
        """

        var events: [ObserverEvent] = []
        try withStatement(sql) { statement in
            sqlite3_bind_int(statement, 1, Int32(limit))

            while sqlite3_step(statement) == SQLITE_ROW {
                if let event = try decodeEvent(from: statement) {
                    events.append(event)
                }
            }
        }

        return events.reversed()
    }

    func pruneEvents(olderThanDays days: Int, keepingTypes: Set<ObserverEventType>) throws {
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
        let keepTypeValues = keepingTypes.map(\.rawValue)
        let placeholders = keepTypeValues.map { _ in "?" }.joined(separator: ",")
        let keepClause = keepTypeValues.isEmpty ? "" : " AND type NOT IN (\(placeholders))"
        let sql = "DELETE FROM events WHERE timestamp < ?\(keepClause);"

        try withStatement(sql) { statement in
            sqlite3_bind_text(statement, 1, isoFormatter.string(from: cutoff), -1, SQLITE_TRANSIENT)
            for (index, type) in keepTypeValues.enumerated() {
                sqlite3_bind_text(statement, Int32(index + 2), type, -1, SQLITE_TRANSIENT)
            }

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw EventStoreError.sqlite(message: lastErrorMessage)
            }
        }
    }

    func eventCountsByType() throws -> [String: Int] {
        let sql = "SELECT type, COUNT(*) FROM events GROUP BY type ORDER BY type;"
        var counts: [String: Int] = [:]

        try withStatement(sql) { statement in
            while sqlite3_step(statement) == SQLITE_ROW {
                counts[columnString(statement, 0)] = Int(sqlite3_column_int(statement, 1))
            }
        }

        return counts
    }

    func archivedActivityInsightCount() throws -> Int {
        let sql = "SELECT COUNT(*) FROM _archive_activity_insight;"
        var count = 0
        try withStatement(sql) { statement in
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }
        return count
    }

    func allEvents(limit: Int = 200_000) throws -> [ObserverEvent] {
        let sql = """
        SELECT id, timestamp, type, source, platform, display_role, app_id,
               confidence, payload_json, workspace_topology_version
        FROM events
        ORDER BY timestamp ASC
        LIMIT ?;
        """

        var events: [ObserverEvent] = []
        try withStatement(sql) { statement in
            sqlite3_bind_int(statement, 1, Int32(limit))
            while sqlite3_step(statement) == SQLITE_ROW {
                if let event = try decodeEvent(from: statement) {
                    events.append(event)
                }
            }
        }
        return events
    }

    func deleteAllEvents() throws {
        try execute("DELETE FROM events;")
    }

    func deleteEvents(since date: Date) throws {
        let sql = "DELETE FROM events WHERE timestamp >= ?;"
        try withStatement(sql) { statement in
            sqlite3_bind_text(statement, 1, isoFormatter.string(from: date), -1, SQLITE_TRANSIENT)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw EventStoreError.sqlite(message: lastErrorMessage)
            }
        }
    }

    private func open() throws {
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            throw EventStoreError.sqlite(message: lastErrorMessage)
        }

        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA synchronous=NORMAL;")
        try execute("PRAGMA foreign_keys=ON;")
    }

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS events (
                rowid INTEGER PRIMARY KEY AUTOINCREMENT,
                id TEXT NOT NULL UNIQUE,
                timestamp TEXT NOT NULL,
                type TEXT NOT NULL,
                source TEXT NOT NULL,
                platform TEXT NOT NULL,
                display_role TEXT,
                app_id TEXT,
                confidence REAL NOT NULL,
                payload_json TEXT NOT NULL,
                workspace_topology_version INTEGER NOT NULL
            );
            """
        )

        try execute("CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp);")
        try execute("CREATE INDEX IF NOT EXISTS idx_events_type_timestamp ON events(type, timestamp);")
        try execute("CREATE INDEX IF NOT EXISTS idx_events_app_timestamp ON events(app_id, timestamp);")
        try archiveLegacyActivityInsights()
    }

    private func archiveLegacyActivityInsights() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS _archive_activity_insight (
                rowid INTEGER PRIMARY KEY,
                id TEXT NOT NULL UNIQUE,
                timestamp TEXT NOT NULL,
                type TEXT NOT NULL,
                source TEXT NOT NULL,
                platform TEXT NOT NULL,
                display_role TEXT,
                app_id TEXT,
                confidence REAL NOT NULL,
                payload_json TEXT NOT NULL,
                workspace_topology_version INTEGER NOT NULL,
                archived_at TEXT NOT NULL
            );
            """
        )
        try execute(
            """
            INSERT OR IGNORE INTO _archive_activity_insight (
                rowid, id, timestamp, type, source, platform, display_role, app_id,
                confidence, payload_json, workspace_topology_version, archived_at
            )
            SELECT rowid, id, timestamp, type, source, platform, display_role, app_id,
                   confidence, payload_json, workspace_topology_version, '\(isoFormatter.string(from: Date()))'
            FROM events
            WHERE type = 'activityInsight';
            """
        )
        try execute("DELETE FROM events WHERE type = 'activityInsight';")
        try execute("CREATE INDEX IF NOT EXISTS idx_archive_activity_insight_timestamp ON _archive_activity_insight(timestamp);")
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw EventStoreError.sqlite(message: lastErrorMessage)
        }
    }

    private func withStatement(_ sql: String, _ body: (OpaquePointer) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw EventStoreError.sqlite(message: lastErrorMessage)
        }
        defer {
            sqlite3_finalize(statement)
        }
        try body(statement)
    }

    private func decodeEvent(from statement: OpaquePointer) throws -> ObserverEvent? {
        guard
            let id = UUID(uuidString: columnString(statement, 0)),
            let timestamp = isoFormatter.date(from: columnString(statement, 1)),
            let type = ObserverEventType(rawValue: columnString(statement, 2))
        else {
            return nil
        }

        let displayRoleRaw = columnOptionalString(statement, 5)
        let payloadJSON = columnString(statement, 8)
        let payloadData = Data(payloadJSON.utf8)
        let payload = (try? payloadDecoder.decode([String: String].self, from: payloadData)) ?? [:]

        return ObserverEvent(
            id: id,
            timestamp: timestamp,
            type: type,
            source: columnString(statement, 3),
            platform: columnString(statement, 4),
            displayRole: displayRoleRaw.flatMap(WorkspaceTopology.DisplayRole.init(rawValue:)),
            appID: columnOptionalString(statement, 6),
            confidence: sqlite3_column_double(statement, 7),
            payload: payload,
            workspaceTopologyVersion: Int(sqlite3_column_int(statement, 9))
        )
    }

    private func payloadJSONString(_ payload: [String: String]) throws -> String {
        let redactedPayload = payload.mapValues(PrivacyRedactor.redact)
        let data = try payloadEncoder.encode(redactedPayload)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EventStoreError.encodingFailed
        }
        return string
    }

    private func bindOptionalText(_ statement: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func columnString(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: text)
    }

    private func columnOptionalString(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return columnString(statement, index)
    }

    private var lastErrorMessage: String {
        guard let database, let message = sqlite3_errmsg(database) else {
            return "unknown SQLite error"
        }
        return String(cString: message)
    }
}

enum EventStoreError: Error {
    case encodingFailed
    case sqlite(message: String)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
