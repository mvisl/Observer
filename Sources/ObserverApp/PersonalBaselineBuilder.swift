import Foundation

struct PersonalBaselineBuilder {
    func samples(
        from events: [ObserverEvent],
        observedHours: Double? = nil,
        includeOverrides: Bool = false,
        calendar: Calendar = .current
    ) -> [PersonalBaselineSample] {
        let eligibleEvents = events.filter { event in
            event.payload["truncated_by_schedule"] != "true"
                && (includeOverrides || event.payload["outside_default_schedule"] != "true")
        }
        let inputEvents = eligibleEvents.filter { $0.type == .inputActivity }
        let focusIntervals = eligibleEvents.filter { $0.type == .appFocusInterval }
        let appFocusEvents = eligibleEvents.filter { $0.type == .appFocus }
        var samples: [PersonalBaselineSample] = []

        if !inputEvents.isEmpty {
            samples.append(contentsOf: groupedSamples(
                metric: "input_tempo_proxy",
                events: inputEvents,
                calendar: calendar
            ) { event in
                let keyboardIdle = Double(event.payload["seconds_since_keyboard"] ?? "") ?? 999
                return 1 / max(keyboardIdle + 1, 1)
            })
        }

        if !focusIntervals.isEmpty {
            samples.append(contentsOf: groupedSamples(
                metric: "focus_block_duration_seconds",
                events: focusIntervals,
                calendar: calendar
            ) { event in
                Double(event.payload["duration_seconds"] ?? "") ?? 0
            })
        }

        if !appFocusEvents.isEmpty {
            let observedHours = max(observedHours ?? 1, 0.1)
            samples.append(contentsOf: groupedSamples(
                metric: "focus_switch_count_per_observed_hour",
                events: appFocusEvents,
                calendar: calendar
            ) { _ in
                1 / observedHours
            })
        }

        return samples
    }

    private func groupedSamples(
        metric: String,
        events: [ObserverEvent],
        calendar: Calendar,
        value: (ObserverEvent) -> Double
    ) -> [PersonalBaselineSample] {
        let grouped = Dictionary(grouping: events) { event -> String in
            let hour = calendar.component(.hour, from: event.timestamp)
            let weekday = calendar.component(.weekday, from: event.timestamp)
            return "\(hour)|\(weekday)"
        }

        return grouped.compactMap { key, group in
            let parts = key.split(separator: "|").compactMap { Int($0) }
            guard parts.count == 2 else {
                return nil
            }
            let values = group.map(value)
            let average = values.reduce(0, +) / Double(max(values.count, 1))
            return PersonalBaselineSample(
                metric: metric,
                hour: parts[0],
                weekday: parts[1],
                value: average,
                sampleCount: values.count
            )
        }
    }
}
