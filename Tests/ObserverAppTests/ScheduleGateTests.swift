import Foundation
import Testing
@testable import ObserverApp

struct ScheduleGateTests {
    @Test func marksDefaultWorkdayBoundariesWithoutStoppingSensors() {
        let calendar = calendar(timeZone: "Europe/Belgrade")
        let gate = ScheduleGate(
            settings: ObserverSettings.defaults.workSchedule,
            calendar: calendar
        )

        let beforeStart = gate.status(at: date(2026, 7, 10, 8, 59, calendar))
        #expect(beforeStart.sensorAllowed == true)
        #expect(beforeStart.outsideDefaultSchedule == true)

        #expect(gate.status(at: date(2026, 7, 10, 9, 0, calendar)).sensorAllowed == true)

        let afterEnd = gate.status(at: date(2026, 7, 10, 18, 1, calendar))
        #expect(afterEnd.sensorAllowed == true)
        #expect(afterEnd.outsideDefaultSchedule == true)
    }

    @Test func overrideAllowsOutsideDefaultScheduleUntilItExpires() {
        let calendar = calendar(timeZone: "Europe/Belgrade")
        let override = ScheduleOverride(
            until: date(2026, 7, 10, 21, 0, calendar),
            reason: "manual_plus_2h"
        )
        let gate = ScheduleGate(
            settings: ObserverSettings.defaults.workSchedule,
            calendar: calendar,
            override: override
        )

        let during = gate.status(at: date(2026, 7, 10, 20, 0, calendar))
        #expect(during.sensorAllowed == true)
        #expect(during.outsideDefaultSchedule == true)

        let after = gate.status(at: date(2026, 7, 10, 21, 1, calendar))
        #expect(after.sensorAllowed == true)
        #expect(after.reason == "off_hours_observing")
    }

    @Test func localTimezoneControlsTheWindow() {
        let utcCalendar = calendar(timeZone: "UTC")
        let belgradeCalendar = calendar(timeZone: "Europe/Belgrade")
        let instant = date(2026, 7, 10, 8, 30, utcCalendar)

        let utcGate = ScheduleGate(
            settings: ObserverSettings.defaults.workSchedule,
            calendar: utcCalendar
        )
        let belgradeGate = ScheduleGate(
            settings: ObserverSettings.defaults.workSchedule,
            calendar: belgradeCalendar
        )

        #expect(utcGate.status(at: instant).sensorAllowed == true)
        #expect(utcGate.status(at: instant).outsideDefaultSchedule == true)
        #expect(belgradeGate.status(at: instant).sensorAllowed == true)
        #expect(belgradeGate.status(at: instant).insideDefaultSchedule == true)
    }

    @Test func optionalHardGateCanStillStopSensorsOutsideSchedule() {
        let calendar = calendar(timeZone: "Europe/Belgrade")
        var settings = ObserverSettings.defaults.workSchedule
        settings.observeOutsideDefaultSchedule = false
        let gate = ScheduleGate(settings: settings, calendar: calendar)

        #expect(gate.status(at: date(2026, 7, 10, 18, 1, calendar)).sensorAllowed == false)
    }

    @Test func suppressesPredictionsNearScheduleEndAndFlagsTruncation() {
        let calendar = calendar(timeZone: "Europe/Belgrade")
        let gate = ScheduleGate(
            settings: ObserverSettings.defaults.workSchedule,
            calendar: calendar
        )

        #expect(gate.predictionAllowed(at: date(2026, 7, 10, 17, 20, calendar)) == true)
        #expect(gate.predictionAllowed(at: date(2026, 7, 10, 17, 40, calendar)) == false)
        #expect(gate.isTruncatedBySchedule(
            start: date(2026, 7, 10, 9, 2, calendar),
            end: date(2026, 7, 10, 10, 0, calendar)
        ) == true)
        #expect(gate.isTruncatedBySchedule(
            start: date(2026, 7, 10, 10, 0, calendar),
            end: date(2026, 7, 10, 17, 58, calendar)
        ) == true)
    }

    private func calendar(timeZone identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
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
}
