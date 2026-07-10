import Foundation

struct ContextPackBuilder {
    let topology: WorkspaceTopology

    func build(events: [ObserverEvent], mode: ObserverController.Mode) -> String {
        let formatter = ISO8601DateFormatter()
        let now = formatter.string(from: Date())
        let appFocusEvents = events.filter { $0.type == .appFocus }
        let attentionEvents = events.filter { $0.type == .attention }
        let detectorEvents = events.filter { $0.type == .detectorFired }
        let userNotes = events.filter { $0.type == .userNote }
        let screenContexts = events.filter { $0.type == .screenContext }
        let ocrContexts = events.filter { $0.type == .ocrContext }
        let inputEvents = events.filter { $0.type == .inputActivity }
        let latestSummary = events.last { $0.type == .localSummary }?.payload["summary"]
        let currentFocus = appFocusEvents.last
        let currentContext = screenContexts.last ?? ocrContexts.last ?? currentFocus
        let transitions = buildTransitions(from: appFocusEvents)
        let observations = buildObservations(
            appFocusEvents: appFocusEvents,
            attentionEvents: attentionEvents,
            inputEvents: inputEvents
        )

        return """
        # Observer Context Pack

        Generated: \(now)
        Mode: \(mode.description)

        ## Current Context

        \(currentContext.map(describePrimaryContext) ?? "- No active context recorded yet.")

        ## Workspace

        \(topology.markdownDescription)

        ## Recent App Flow

        \(transitions.isEmpty ? "- No app switches recorded yet." : transitions.joined(separator: "\n"))

        ## User Notes

        \(describeUserNotes(userNotes))

        ## Recent Screen Context

        \(describeScreenContexts(screenContexts))

        ## Recent OCR Context

        \(describeOCRContexts(ocrContexts))

        ## Attention Signal

        \(describeAttention(attentionEvents))

        ## Local Detectors

        \(describeDetectors(detectorEvents))

        ## Latest Local Summary

        \(latestSummary ?? "- No local summary generated yet.")

        ## Local Observations

        \(observations.isEmpty ? "- Not enough signal yet." : observations.joined(separator: "\n"))

        ## Raw Recent Events

        \(describeRecentEvents(events.suffix(12), formatter: formatter))

        ## Privacy Notes

        This context was generated locally. It does not include raw screenshots, camera frames, video, audio, typed characters, or content from apps that were not explicitly allowed.
        """
    }

    private func describePrimaryContext(_ event: ObserverEvent) -> String {
        switch event.type {
        case .screenContext:
            return compactLines([
                requiredLine("App", event.payload["app_name"] ?? event.appID ?? "unknown"),
                optionalLine("Window", event.payload["window_title"]),
                optionalLine("Document", event.payload["document"]),
                optionalLine("Focused element", event.payload["focused_element_role"]),
                optionalLine("Selected text", event.payload["selected_text"]),
                optionalLine("Element value", event.payload["focused_element_value"]),
                optionalLine("Display", event.payload["display_role"])
            ])

        case .appFocus:
            return compactLines([
                requiredLine("App", event.payload["app_name"] ?? event.appID ?? "unknown"),
                optionalLine("Window title available", event.payload["accessibility_window_title_available"]),
                optionalLine("Content allowed", event.payload["content_allowed"]),
                optionalLine("Display", event.payload["display_role"])
            ])

        default:
            return "- \(event.type.rawValue): \(event.payloadSummary)"
        }
    }

    private func buildTransitions(from appFocusEvents: [ObserverEvent]) -> [String] {
        let events = appFocusEvents.suffix(10)
        return events.map { event in
            let app = event.payload["app_name"] ?? event.appID ?? "unknown"
            let display = event.payload["display_role"].map { " on \($0)" } ?? ""
            let content = event.payload["content_allowed"] == "true" ? "" : " (content not allowed)"
            return "- \(app)\(display)\(content)"
        }
    }

    private func describeScreenContexts(_ screenContexts: [ObserverEvent]) -> String {
        let contexts = screenContexts.suffix(5)
        guard !contexts.isEmpty else {
            return "- No allowlisted screen context captured yet."
        }

        return contexts.map { event in
            let app = event.payload["app_name"] ?? event.appID ?? "unknown"
            let window = event.payload["window_title"].map { " · \($0)" } ?? ""
            let selected = event.payload["selected_text"].map { " · selected: \($0)" } ?? ""
            let value = event.payload["focused_element_value"].map { " · value: \($0)" } ?? ""
            return "- \(app)\(window)\(selected)\(value)"
        }.joined(separator: "\n")
    }

    private func describeUserNotes(_ userNotes: [ObserverEvent]) -> String {
        let notes = userNotes.suffix(5)
        guard !notes.isEmpty else {
            return "- No user notes captured."
        }

        return notes.map { event in
            "- \(event.payload["note"] ?? "")"
        }.joined(separator: "\n")
    }

    private func describeOCRContexts(_ ocrContexts: [ObserverEvent]) -> String {
        let contexts = ocrContexts.suffix(3)
        guard !contexts.isEmpty else {
            return "- No OCR context captured yet."
        }

        return contexts.map { event in
            let app = event.payload["app_name"] ?? event.appID ?? "unknown"
            let text = event.payload["text"] ?? ""
            return "- \(app) · OCR: \(text)"
        }.joined(separator: "\n")
    }

    private func describeAttention(_ attentionEvents: [ObserverEvent]) -> String {
        guard let latest = attentionEvents.last else {
            return "- Camera attention is not running or no attention events have been recorded."
        }

        let face = latest.payload["face_present"] == "true" ? "present" : "not present"
        let zone = latest.payload["attention_zone"] ?? "unknown"
        let position = latest.payload["face_position"] ?? "unknown"
        let count = latest.payload["face_count"] ?? "0"
        return "- Face: \(face), zone: \(zone), position: \(position), detected faces: \(count)."
    }

    private func describeDetectors(_ detectorEvents: [ObserverEvent]) -> String {
        let detectors = detectorEvents.suffix(5)
        guard !detectors.isEmpty else {
            return "- No local detectors fired recently."
        }

        return detectors.map { event in
            let detector = event.payload["detector"] ?? "unknown"
            let interpretation = event.payload["interpretation"] ?? "no interpretation"
            return "- \(detector): \(interpretation)"
        }.joined(separator: "\n")
    }

    private func buildObservations(
        appFocusEvents: [ObserverEvent],
        attentionEvents: [ObserverEvent],
        inputEvents: [ObserverEvent]
    ) -> [String] {
        var observations: [String] = []
        let recentApps = appFocusEvents.suffix(20).compactMap { $0.payload["app_name"] }
        let uniqueApps = Set(recentApps)

        if recentApps.count >= 6 && uniqueApps.count >= 2 {
            observations.append("- There were \(recentApps.count) recent app focus changes across \(uniqueApps.count) apps.")
        }

        if let lastInput = inputEvents.last,
           let idleText = lastInput.payload["seconds_since_any_input"],
           let idle = Double(idleText) {
            if idle < 10 {
                observations.append("- Input was active recently; avoid interrupting during typing.")
            } else if idle > 180 {
                observations.append("- There has been no recent input; this may be reading, thinking, or absence.")
            }
        }

        let notAllowedCount = appFocusEvents.suffix(20).filter { $0.payload["content_allowed"] == "false" }.count
        if notAllowedCount > 0 {
            observations.append("- \(notAllowedCount) recent focus events had content disabled by privacy allowlist.")
        }

        if let latestAttention = attentionEvents.last {
            if latestAttention.payload["face_present"] == "false" {
                observations.append("- Camera attention currently says the face is off screen.")
            } else {
                observations.append("- Camera attention currently sees a face near the camera.")
            }
        }

        return observations
    }

    private func describeRecentEvents(_ events: ArraySlice<ObserverEvent>, formatter: ISO8601DateFormatter) -> String {
        guard !events.isEmpty else {
            return "- No events recorded yet."
        }

        return events.map { event in
            "- \(formatter.string(from: event.timestamp)) | \(event.type.rawValue) | \(event.payloadSummary)"
        }.joined(separator: "\n")
    }

    private func requiredLine(_ label: String, _ value: String) -> String {
        "- \(label): \(value)"
    }

    private func optionalLine(_ label: String, _ value: String?) -> String {
        guard let value, !value.isEmpty else {
            return ""
        }
        return "- \(label): \(value)"
    }

    private func compactLines(_ lines: [String]) -> String {
        let compacted = lines.filter { !$0.isEmpty }
        return compacted.isEmpty ? "- No active context recorded yet." : compacted.joined(separator: "\n")
    }
}

private extension ObserverController.Mode {
    var description: String {
        switch self {
        case .paused:
            return "paused"
        case .observing:
            return "observing"
        }
    }
}

extension ObserverEvent {
    var payloadSummary: String {
        if payload.isEmpty {
            return "no payload"
        }
        return payload
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }
}
