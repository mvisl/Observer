import Foundation
import SQLite3

struct ObservedInterval: Codable, Equatable {
    let start: Date
    let end: Date
    let outsideDefaultSchedule: Bool
}

struct ObservationCalendarDay: Equatable {
    let date: String
    let plannedStart: Date?
    let plannedEnd: Date?
    let observedIntervals: [ObservedInterval]
    let coverageRatio: Double
    let offReason: String

    var observedSeconds: TimeInterval {
        observedIntervals.reduce(0) { total, interval in
            total + max(0, interval.end.timeIntervalSince(interval.start))
        }
    }

    var plannedSeconds: TimeInterval {
        guard let plannedStart, let plannedEnd else {
            return 0
        }
        return max(0, plannedEnd.timeIntervalSince(plannedStart))
    }
}

final class ObservationCalendarStore {
    private let databaseURL: URL
    private let encoder = JSONEncoder.observerEncoder
    private let decoder = JSONDecoder.observerDecoder
    private let isoFormatter = ISO8601DateFormatter()
    private var database: OpaquePointer?

    init(directory: URL) throws {
        self.databaseURL = directory.appendingPathComponent("observation-calendar.sqlite")
        try open()
        try migrate()
    }

    deinit {
        sqlite3_close(database)
    }

    func recordInterval(
        start: Date,
        end: Date,
        plannedStart: Date?,
        plannedEnd: Date?,
        outsideDefaultSchedule: Bool,
        offReason: String = "none"
    ) throws {
        let dateKey = Self.dateKey(for: start)
        let existing = try day(dateKey)
        var intervals = existing?.observedIntervals ?? []
        intervals.append(
            ObservedInterval(
                start: start,
                end: max(end, start),
                outsideDefaultSchedule: outsideDefaultSchedule
            )
        )
        try upsert(
            ObservationCalendarDay(
                date: dateKey,
                plannedStart: plannedStart ?? existing?.plannedStart,
                plannedEnd: plannedEnd ?? existing?.plannedEnd,
                observedIntervals: intervals,
                coverageRatio: Self.coverageRatio(
                    intervals: intervals,
                    plannedStart: plannedStart ?? existing?.plannedStart,
                    plannedEnd: plannedEnd ?? existing?.plannedEnd
                ),
                offReason: offReason == "none" ? (existing?.offReason ?? "none") : offReason
            )
        )
    }

    func markOff(date: String, reason: String) throws {
        let existing = try day(date)
        try upsert(
            ObservationCalendarDay(
                date: date,
                plannedStart: existing?.plannedStart,
                plannedEnd: existing?.plannedEnd,
                observedIntervals: existing?.observedIntervals ?? [],
                coverageRatio: existing?.coverageRatio ?? 0,
                offReason: reason
            )
        )
    }

    func day(_ date: String) throws -> ObservationCalendarDay? {
        let sql = """
        SELECT date, planned_start, planned_end, observed_intervals_json, coverage_ratio, off_reason
        FROM observation_calendar
        WHERE date = ?;
        """
        var result: ObservationCalendarDay?
        try withStatement(sql) { statement in
            sqlite3_bind_text(statement, 1, date, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return
            }
            result = decodeDay(statement)
        }
        return result
    }

    func days(since start: Date, until end: Date) throws -> [ObservationCalendarDay] {
        let sql = """
        SELECT date, planned_start, planned_end, observed_intervals_json, coverage_ratio, off_reason
        FROM observation_calendar
        WHERE date >= ? AND date <= ?
        ORDER BY date ASC;
        """
        var result: [ObservationCalendarDay] = []
        try withStatement(sql) { statement in
            sqlite3_bind_text(statement, 1, Self.dateKey(for: start), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, Self.dateKey(for: end), -1, SQLITE_TRANSIENT)
            while sqlite3_step(statement) == SQLITE_ROW {
                result.append(decodeDay(statement))
            }
        }
        return result
    }

    func observedHours(since start: Date, until end: Date) throws -> Double {
        try days(since: start, until: end).reduce(0) { total, day in
            total + day.observedSeconds / 3600
        }
    }

    private func upsert(_ day: ObservationCalendarDay) throws {
        let data = try encoder.encode(day.observedIntervals)
        let intervalsJSON = String(data: data, encoding: .utf8) ?? "[]"
        try withStatement(
            """
            INSERT INTO observation_calendar (
                date, planned_start, planned_end, observed_intervals_json, coverage_ratio, off_reason
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(date) DO UPDATE SET
                planned_start = excluded.planned_start,
                planned_end = excluded.planned_end,
                observed_intervals_json = excluded.observed_intervals_json,
                coverage_ratio = excluded.coverage_ratio,
                off_reason = excluded.off_reason;
            """
        ) { statement in
            sqlite3_bind_text(statement, 1, day.date, -1, SQLITE_TRANSIENT)
            bindDate(statement, 2, day.plannedStart)
            bindDate(statement, 3, day.plannedEnd)
            sqlite3_bind_text(statement, 4, intervalsJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 5, day.coverageRatio)
            sqlite3_bind_text(statement, 6, day.offReason, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw ObservationCalendarStoreError.sqlite(message: lastErrorMessage)
            }
        }
    }

    private func decodeDay(_ statement: OpaquePointer) -> ObservationCalendarDay {
        let data = Data(columnString(statement, 3).utf8)
        let intervals = (try? decoder.decode([ObservedInterval].self, from: data)) ?? []
        return ObservationCalendarDay(
            date: columnString(statement, 0),
            plannedStart: columnOptionalString(statement, 1).flatMap(isoFormatter.date(from:)),
            plannedEnd: columnOptionalString(statement, 2).flatMap(isoFormatter.date(from:)),
            observedIntervals: intervals,
            coverageRatio: sqlite3_column_double(statement, 4),
            offReason: columnString(statement, 5)
        )
    }

    private static func coverageRatio(intervals: [ObservedInterval], plannedStart: Date?, plannedEnd: Date?) -> Double {
        guard let plannedStart, let plannedEnd else {
            return 0
        }
        let plannedSeconds = max(0, plannedEnd.timeIntervalSince(plannedStart))
        guard plannedSeconds > 0 else {
            return 0
        }
        let observedSeconds = intervals.reduce(0) { total, interval in
            total + max(0, interval.end.timeIntervalSince(interval.start))
        }
        return min(1, observedSeconds / plannedSeconds)
    }

    private func open() throws {
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            throw ObservationCalendarStoreError.sqlite(message: lastErrorMessage)
        }
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA synchronous=NORMAL;")
    }

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS observation_calendar (
                date TEXT PRIMARY KEY,
                planned_start TEXT,
                planned_end TEXT,
                observed_intervals_json TEXT NOT NULL,
                coverage_ratio REAL NOT NULL,
                off_reason TEXT NOT NULL
            );
            """
        )
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw ObservationCalendarStoreError.sqlite(message: lastErrorMessage)
        }
    }

    private func withStatement(_ sql: String, _ body: (OpaquePointer) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ObservationCalendarStoreError.sqlite(message: lastErrorMessage)
        }
        defer {
            sqlite3_finalize(statement)
        }
        try body(statement)
    }

    private func bindDate(_ statement: OpaquePointer, _ index: Int32, _ date: Date?) {
        if let date {
            sqlite3_bind_text(statement, index, isoFormatter.string(from: date), -1, SQLITE_TRANSIENT)
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

    static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

enum ObservationCalendarStoreError: Error {
    case sqlite(message: String)
}

struct HolidayICSImporter {
    func dates(from ics: String) -> [String] {
        ics
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                guard line.hasPrefix("DTSTART") else {
                    return nil
                }
                guard let raw = line.components(separatedBy: ":").last else {
                    return nil
                }
                let digits = raw.filter(\.isNumber)
                guard digits.count >= 8 else {
                    return nil
                }
                let year = digits.prefix(4)
                let month = digits.dropFirst(4).prefix(2)
                let day = digits.dropFirst(6).prefix(2)
                return "\(year)-\(month)-\(day)"
            }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
