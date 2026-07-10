import Foundation

struct LocalSummaryBuilder {
    func build(events: [ObserverEvent]) -> String {
        let formatter = ISO8601DateFormatter()
        let appFocusEvents = events.filter { $0.type == .appFocus }
        let focusIntervals = events.filter { $0.type == .appFocusInterval }
        let attentionEvents = events.filter { $0.type == .attention }
        let detectorEvents = events.filter { $0.type == .detectorFired }
        let userNotes = events.filter { $0.type == .userNote }
        let screenContexts = events.filter { $0.type == .screenContext }
        let writingContexts = events.filter { $0.type == .writingContext }
        let ocrContexts = events.filter { $0.type == .ocrContext }
        let inputEvents = events.filter { $0.type == .inputActivity }
        let startedAt = events.first?.timestamp
        let endedAt = events.last?.timestamp
        let topApps = describeTopApps(appFocusEvents: appFocusEvents, focusIntervals: focusIntervals)

        let contentAllowedCount = appFocusEvents.filter { $0.payload["content_allowed"] == "true" }.count
        let contentBlockedCount = appFocusEvents.filter { $0.payload["content_allowed"] == "false" }.count
        let latestContext = writingContexts.last.map(describeScreenContext)
            ?? screenContexts.last.map(describeScreenContext)
            ?? ocrContexts.last.map(describeOCRContext)
            ?? "- No allowlisted screen context captured."
        let inputLine = inputEvents.last.map(describeInput) ?? "- No input activity sample yet."

        return """
        # Observer Local Summary

        Window: \(startedAt.map(formatter.string(from:)) ?? "unknown") -> \(endedAt.map(formatter.string(from:)) ?? "unknown")
        Events analyzed: \(events.count)

        ## Main Apps

        \(topApps)

        ## Latest Allowlisted Context

        \(latestContext)

        ## User Notes

        \(describeUserNotes(userNotes))

        ## Input

        \(inputLine)

        ## Attention

        \(describeAttention(attentionEvents))

        ## Detectors

        \(describeDetectors(detectorEvents))

        ## Privacy

        - Content allowed focus events: \(contentAllowedCount)
        - Content blocked focus events: \(contentBlockedCount)

        ## Early Read

        \(earlyRead(appFocusEvents: appFocusEvents, screenContexts: screenContexts + writingContexts, inputEvents: inputEvents))
        """
    }

    private func countApps(_ events: [ObserverEvent]) -> [String: Int] {
        events.reduce(into: [String: Int]()) { result, event in
            let app = event.payload["app_name"] ?? event.appID ?? "unknown"
            result[app, default: 0] += 1
        }
    }

    private func describeTopApps(appFocusEvents: [ObserverEvent], focusIntervals: [ObserverEvent]) -> String {
        let durations = focusIntervals.reduce(into: [String: Double]()) { result, event in
            let app = event.payload["app_name"] ?? event.appID ?? "unknown"
            let duration = Double(event.payload["duration_seconds"] ?? "0") ?? 0
            result[app, default: 0] += duration
        }

        if !durations.isEmpty {
            return durations
                .sorted { $0.value > $1.value }
                .prefix(6)
                .map { "- \($0.key): \(Int($0.value))s focused" }
                .joined(separator: "\n")
        }

        let appCounts = countApps(appFocusEvents)
        return appCounts
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map { "- \($0.key): \($0.value) focus event(s)" }
            .joined(separator: "\n")
            .ifEmpty("- No app focus events yet.")
    }

    private func describeScreenContext(_ event: ObserverEvent) -> String {
        let app = event.payload["app_name"] ?? event.appID ?? "unknown"
        let window = event.payload["window_title"].map { "\n- Window: \($0)" } ?? ""
        let selected = event.payload["selected_text"].map { "\n- Selected text: \($0)" } ?? ""
        let value = event.payload["focused_element_value"].map { "\n- Focused value: \($0)" } ?? ""
        return "- App: \(app)\(window)\(selected)\(value)"
    }

    private func describeOCRContext(_ event: ObserverEvent) -> String {
        let app = event.payload["app_name"] ?? event.appID ?? "unknown"
        let text = event.payload["text"] ?? ""
        return "- App: \(app)\n- OCR: \(text)"
    }

    private func describeInput(_ event: ObserverEvent) -> String {
        let any = event.payload["seconds_since_any_input"] ?? "unknown"
        let keyboard = event.payload["seconds_since_keyboard"] ?? "unknown"
        let click = event.payload["seconds_since_click"] ?? "unknown"
        return "- Last sample: any input \(any)s ago, keyboard \(keyboard)s ago, click \(click)s ago."
    }

    private func describeUserNotes(_ events: [ObserverEvent]) -> String {
        let notes = events.suffix(5)
        guard !notes.isEmpty else {
            return "- No user notes."
        }

        return notes.map { event in
            "- \(event.payload["note"] ?? "")"
        }.joined(separator: "\n")
    }

    private func describeAttention(_ events: [ObserverEvent]) -> String {
        guard let latest = events.last else {
            return "- Camera attention was not sampled."
        }

        let face = latest.payload["face_present"] == "true" ? "present" : "not present"
        let zone = latest.payload["attention_zone"] ?? "unknown"
        let position = latest.payload["face_position"] ?? "unknown"
        return "- Latest camera signal: face \(face), zone \(zone), position \(position)."
    }

    private func describeDetectors(_ events: [ObserverEvent]) -> String {
        let detectors = events.suffix(5)
        guard !detectors.isEmpty else {
            return "- No detector fired recently."
        }

        return detectors.map { event in
            let detector = event.payload["detector"] ?? "unknown"
            let interpretation = event.payload["interpretation"] ?? "no interpretation"
            return "- \(detector): \(interpretation)"
        }.joined(separator: "\n")
    }

    private func earlyRead(
        appFocusEvents: [ObserverEvent],
        screenContexts: [ObserverEvent],
        inputEvents: [ObserverEvent]
    ) -> String {
        var lines: [String] = []
        let appSwitchCount = appFocusEvents.count
        let uniqueAppCount = Set(appFocusEvents.compactMap { $0.payload["app_name"] ?? $0.appID }).count

        if appSwitchCount >= 8 {
            lines.append("- Many app focus changes were observed: \(appSwitchCount) across \(uniqueAppCount) apps.")
        } else {
            lines.append("- Focus flow is still sparse; observe longer for stronger patterns.")
        }

        if screenContexts.isEmpty {
            lines.append("- No allowlisted content yet; use `Allow Current App Context` for apps where window context is useful.")
        } else {
            lines.append("- Allowlisted content is available, so context packs can include richer app/window context.")
        }

        if let lastInput = inputEvents.last,
           let idleText = lastInput.payload["seconds_since_any_input"],
           let idle = Double(idleText),
           idle < 10 {
            lines.append("- Recent input is active; push hints should stay quiet.")
        }

        return lines.joined(separator: "\n")
    }
}
