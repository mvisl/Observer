import Foundation
import SQLite3

struct PersonalBaselineSample: Equatable {
    let metric: String
    let hour: Int
    let weekday: Int
    let value: Double
    let sampleCount: Int
}

final class PersonalBaselineStore {
    private let databaseURL: URL
    private let isoFormatter = ISO8601DateFormatter()
    private var database: OpaquePointer?

    init(directory: URL) throws {
        self.databaseURL = directory.appendingPathComponent("personal-baselines.sqlite")
        try open()
        try migrate()
    }

    deinit {
        sqlite3_close(database)
    }

    func upsert(sample: PersonalBaselineSample, at date: Date = Date()) throws {
        let existing = try baseline(metric: sample.metric, hour: sample.hour, weekday: sample.weekday)
        let newCount = (existing?.sampleCount ?? 0) + sample.sampleCount
        let oldValue = existing?.value ?? sample.value
        let blended = existing == nil
            ? sample.value
            : ((oldValue * Double(existing?.sampleCount ?? 0)) + (sample.value * Double(sample.sampleCount))) / Double(max(newCount, 1))

        try withStatement(
            """
            INSERT INTO personal_baselines (metric, hour, weekday, value, sample_count, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(metric, hour, weekday)
            DO UPDATE SET value = excluded.value, sample_count = excluded.sample_count, updated_at = excluded.updated_at;
            """
        ) { statement in
            sqlite3_bind_text(statement, 1, sample.metric, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 2, Int32(sample.hour))
            sqlite3_bind_int(statement, 3, Int32(sample.weekday))
            sqlite3_bind_double(statement, 4, blended)
            sqlite3_bind_int(statement, 5, Int32(newCount))
            sqlite3_bind_text(statement, 6, isoFormatter.string(from: date), -1, SQLITE_TRANSIENT)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw PersonalBaselineStoreError.sqlite(message: lastErrorMessage)
            }
        }
    }

    func recent(limit: Int = 40) throws -> [PersonalBaselineSample] {
        let sql = """
        SELECT metric, hour, weekday, value, sample_count
        FROM personal_baselines
        ORDER BY updated_at DESC
        LIMIT ?;
        """
        var samples: [PersonalBaselineSample] = []
        try withStatement(sql) { statement in
            sqlite3_bind_int(statement, 1, Int32(limit))
            while sqlite3_step(statement) == SQLITE_ROW {
                samples.append(
                    PersonalBaselineSample(
                        metric: columnString(statement, 0),
                        hour: Int(sqlite3_column_int(statement, 1)),
                        weekday: Int(sqlite3_column_int(statement, 2)),
                        value: sqlite3_column_double(statement, 3),
                        sampleCount: Int(sqlite3_column_int(statement, 4))
                    )
                )
            }
        }
        return samples
    }

    private func baseline(metric: String, hour: Int, weekday: Int) throws -> PersonalBaselineSample? {
        let sql = """
        SELECT metric, hour, weekday, value, sample_count
        FROM personal_baselines
        WHERE metric = ? AND hour = ? AND weekday = ?;
        """
        var result: PersonalBaselineSample?
        try withStatement(sql) { statement in
            sqlite3_bind_text(statement, 1, metric, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 2, Int32(hour))
            sqlite3_bind_int(statement, 3, Int32(weekday))
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return
            }
            result = PersonalBaselineSample(
                metric: columnString(statement, 0),
                hour: Int(sqlite3_column_int(statement, 1)),
                weekday: Int(sqlite3_column_int(statement, 2)),
                value: sqlite3_column_double(statement, 3),
                sampleCount: Int(sqlite3_column_int(statement, 4))
            )
        }
        return result
    }

    private func open() throws {
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            throw PersonalBaselineStoreError.sqlite(message: lastErrorMessage)
        }
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA synchronous=NORMAL;")
    }

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS personal_baselines (
                metric TEXT NOT NULL,
                hour INTEGER NOT NULL,
                weekday INTEGER NOT NULL,
                value REAL NOT NULL,
                sample_count INTEGER NOT NULL,
                updated_at TEXT NOT NULL,
                PRIMARY KEY(metric, hour, weekday)
            );
            """
        )
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw PersonalBaselineStoreError.sqlite(message: lastErrorMessage)
        }
    }

    private func withStatement(_ sql: String, _ body: (OpaquePointer) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw PersonalBaselineStoreError.sqlite(message: lastErrorMessage)
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
}

enum PersonalBaselineStoreError: Error {
    case sqlite(message: String)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
