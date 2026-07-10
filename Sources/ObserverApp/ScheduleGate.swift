import Foundation

struct ScheduleOverride: Equatable {
    let until: Date
    let reason: String
}

struct ScheduleGateStatus: Equatable {
    let sensorAllowed: Bool
    let insideDefaultSchedule: Bool
    let outsideDefaultSchedule: Bool
    let reason: String
    let secondsUntilEnd: TimeInterval?
}

struct ScheduleGate {
    let settings: ObserverSettings.WorkScheduleSettings
    var calendar: Calendar = .autoupdatingCurrent
    var override: ScheduleOverride?

    func status(at date: Date = Date()) -> ScheduleGateStatus {
        guard settings.enabled else {
            return ScheduleGateStatus(
                sensorAllowed: true,
                insideDefaultSchedule: true,
                outsideDefaultSchedule: false,
                reason: "schedule_disabled",
                secondsUntilEnd: nil
            )
        }

        let defaultAllowed = isInsideDefaultSchedule(date)
        if defaultAllowed {
            return ScheduleGateStatus(
                sensorAllowed: true,
                insideDefaultSchedule: true,
                outsideDefaultSchedule: false,
                reason: "in_schedule",
                secondsUntilEnd: workEnd(on: date).map { $0.timeIntervalSince(date) }
            )
        }

        if let override, override.until > date {
            return ScheduleGateStatus(
                sensorAllowed: true,
                insideDefaultSchedule: false,
                outsideDefaultSchedule: true,
                reason: "schedule_override",
                secondsUntilEnd: override.until.timeIntervalSince(date)
            )
        }

        if settings.observeOutsideDefaultSchedule {
            return ScheduleGateStatus(
                sensorAllowed: true,
                insideDefaultSchedule: false,
                outsideDefaultSchedule: true,
                reason: isDayOff(date) ? "day_off_observing" : "off_hours_observing",
                secondsUntilEnd: nil
            )
        }

        return ScheduleGateStatus(
            sensorAllowed: false,
            insideDefaultSchedule: false,
            outsideDefaultSchedule: false,
            reason: isDayOff(date) ? "day_off" : "off_hours",
            secondsUntilEnd: nil
        )
    }

    func predictionAllowed(at date: Date = Date()) -> Bool {
        let current = status(at: date)
        guard current.sensorAllowed else {
            return false
        }
        guard let secondsUntilEnd = current.secondsUntilEnd else {
            return true
        }
        return secondsUntilEnd > settings.predictionSuppressionBeforeEndSeconds
    }

    func isTruncatedBySchedule(start: Date?, end: Date) -> Bool {
        guard settings.enabled else {
            return false
        }
        if let start, secondsSinceStartBoundary(start) <= settings.boundaryTruncationMarginSeconds {
            return true
        }
        if secondsUntilEndBoundary(end) <= settings.boundaryTruncationMarginSeconds {
            return true
        }
        return false
    }

    func isInsideDefaultSchedule(_ date: Date) -> Bool {
        guard !isDayOff(date),
              settings.weekdays.contains(calendar.component(.weekday, from: date)),
              let start = workStart(on: date),
              let end = workEnd(on: date)
        else {
            return false
        }
        return date >= start && date < end
    }

    func workStart(on date: Date) -> Date? {
        calendar.date(
            bySettingHour: settings.startHour,
            minute: settings.startMinute,
            second: 0,
            of: date
        )
    }

    func workEnd(on date: Date) -> Date? {
        calendar.date(
            bySettingHour: settings.endHour,
            minute: settings.endMinute,
            second: 0,
            of: date
        )
    }

    private func isDayOff(_ date: Date) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return settings.daysOff.contains(formatter.string(from: date))
    }

    private func secondsSinceStartBoundary(_ date: Date) -> TimeInterval {
        guard let start = workStart(on: date), date >= start else {
            return .greatestFiniteMagnitude
        }
        return date.timeIntervalSince(start)
    }

    private func secondsUntilEndBoundary(_ date: Date) -> TimeInterval {
        guard let end = workEnd(on: date), date <= end else {
            return .greatestFiniteMagnitude
        }
        return end.timeIntervalSince(date)
    }
}
