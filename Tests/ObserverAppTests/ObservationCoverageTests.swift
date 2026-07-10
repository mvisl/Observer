import Foundation
import Testing
@testable import ObserverApp

struct ObservationCoverageTests {
    @Test func recordsPartialCoverageAndManualDayOff() throws {
        let directory = try temporaryDirectory()
        let store = try ObservationCalendarStore(directory: directory)
        let calendar = calendar()
        let start = date(2026, 7, 10, 9, 0, calendar)
        let end = date(2026, 7, 10, 12, 0, calendar)
        let plannedStart = date(2026, 7, 10, 9, 0, calendar)
        let plannedEnd = date(2026, 7, 10, 18, 0, calendar)

        try store.recordInterval(
            start: start,
            end: end,
            plannedStart: plannedStart,
            plannedEnd: plannedEnd,
            outsideDefaultSchedule: false
        )
        try store.markOff(date: "2026-07-10", reason: "day_off")

        let loadedDay = try store.day("2026-07-10")
        let day = try #require(loadedDay)
        #expect(day.offReason == "day_off")
        #expect(abs(day.coverageRatio - (3.0 / 9.0)) < 0.001)
        #expect(abs(try store.observedHours(since: start, until: plannedEnd) - 3.0) < 0.001)
    }

    @Test func importsHolidayDatesFromICS() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20260101
        SUMMARY:Holiday
        END:VEVENT
        END:VCALENDAR
        """

        #expect(HolidayICSImporter().dates(from: ics) == ["2026-01-01"])
    }

    @Test func baselinesSkipTruncatedAndOverrideEvents() throws {
        let calendar = calendar()
        let base = date(2026, 7, 10, 10, 0, calendar)
        let events = [
            event(.appFocus, at: base, payload: ["app_name": "Xcode"]),
            event(.appFocus, at: base.addingTimeInterval(60), payload: ["app_name": "Xcode"]),
            event(.appFocus, at: base.addingTimeInterval(120), payload: [
                "app_name": "Chrome",
                "outside_default_schedule": "true"
            ]),
            event(.appFocusInterval, at: base.addingTimeInterval(180), payload: [
                "duration_seconds": "120",
                "truncated_by_schedule": "true"
            ])
        ]

        let samples = PersonalBaselineBuilder().samples(
            from: events,
            observedHours: 2,
            includeOverrides: false,
            calendar: calendar
        )

        let switchSample = try #require(samples.first { $0.metric == "focus_switch_count_per_observed_hour" })
        #expect(switchSample.sampleCount == 2)
        #expect(abs(switchSample.value - 0.5) < 0.001)
        #expect(samples.contains { $0.metric == "focus_block_duration_seconds" } == false)
    }

    @Test func sequenceMiningDoesNotCrossObservationGap() {
        var cognitive = ObserverSettings.defaults.cognitiveSettings
        cognitive.sequenceMinimumSupport = 1
        cognitive.sequenceMinimumConfidence = 0.1
        let now = Date()
        let events = [
            event(.appFocus, at: now, payload: ["app_name": "Chrome"]),
            event(.contentContext, at: now.addingTimeInterval(1), payload: ["content_kind": "feed"]),
            event(.observationGap, at: now.addingTimeInterval(2), payload: ["duration_days": "3"]),
            event(.appFocus, at: now.addingTimeInterval(3), payload: ["app_name": "Xcode"]),
            event(.inputActivity, at: now.addingTimeInterval(4), payload: ["seconds_since_any_input": "1"]),
            event(.cognitiveState, at: now.addingTimeInterval(5), payload: ["state": "flow"])
        ]

        let patterns = SequenceMiningBuilder(settings: cognitive).mine(events: events)

        #expect(patterns.isEmpty == false)
        #expect(patterns.allSatisfy { !$0.antecedentChain.contains("focus:browser") })
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("observer-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Belgrade")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ calendar: Calendar) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    private func event(_ type: ObserverEventType, at timestamp: Date, payload: [String: String]) -> ObserverEvent {
        ObserverEvent(
            id: UUID(),
            timestamp: timestamp,
            type: type,
            source: "test",
            platform: "macOS",
            displayRole: nil,
            appID: nil,
            confidence: 0.8,
            payload: payload,
            workspaceTopologyVersion: 1
        )
    }
}
