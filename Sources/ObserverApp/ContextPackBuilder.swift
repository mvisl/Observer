import Foundation

struct ContextPackBuilder {
    let topology: WorkspaceTopology
    var pseudonymizeEntities: Bool = true
    var entityAggregates: [String: [String: String]] = [:]

    func build(events: [ObserverEvent], mode: ObserverController.Mode) -> String {
        let formatter = ISO8601DateFormatter()
        let now = formatter.string(from: Date())
        let appFocusEvents = events.filter { $0.type == .appFocus }
        let attentionEvents = events.filter { $0.type == .attention }
        let behaviorCueEvents = events.filter { $0.type == .behaviorCue }
        let gazeCalibrationEvents = events.filter { $0.type == .gazeCalibrationSample }
        let detectorEvents = events.filter { $0.type == .detectorFired }
        let userNotes = events.filter { $0.type == .userNote }
        let screenContexts = events.filter { $0.type == .screenContext }
        let writingContexts = events.filter { $0.type == .writingContext }
        let ocrContexts = events.filter { $0.type == .ocrContext }
        let contentContexts = events.filter { $0.type == .contentContext }
        let boundReactions = events.filter { $0.type == .boundReaction }
        let inputEvents = events.filter { $0.type == .inputActivity }
        let activityInsightEvents = events.filter { $0.type == .activityInsight }
        let mediaEvents = events.filter { $0.type == .mediaPlayback }
        let mediaReactionEvents = events.filter { $0.type == .mediaReaction }
        let latestSummary = events.last { $0.type == .localSummary }?.payload["summary"]
        let currentFocus = appFocusEvents.last
        let currentContext = contentContexts.last ?? writingContexts.last ?? screenContexts.last ?? ocrContexts.last ?? currentFocus
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

        ## Active Writing Context

        \(describeWritingContexts(writingContexts))

        ## Recent OCR Context

        \(describeOCRContexts(ocrContexts))

        ## Content Context

        \(describeContentContexts(contentContexts))

        ## Bound Reactions

        \(describeBoundReactions(boundReactions))

        ## Entity Aggregates

        \(describeEntityAggregates(entityAggregates))

        ## Attention Signal

        \(describeAttention(attentionEvents))

        ## Behavior Cues

        \(describeBehaviorCues(behaviorCueEvents))

        ## Gaze Calibration

        \(describeGazeCalibration(gazeCalibrationEvents))

        ## Local Detectors

        \(describeDetectors(detectorEvents))

        ## Activity Insights

        \(describeActivityInsights(activityInsightEvents))

        ## Media Playback

        \(describeMediaPlayback(mediaEvents))

        ## Media Reactions

        \(describeMediaReactions(mediaReactionEvents))

        ## Latest Local Summary

        \(latestSummary ?? "- No local summary generated yet.")

        ## Local Observations

        \(observations.isEmpty ? "- Not enough signal yet." : observations.joined(separator: "\n"))

        ## Raw Recent Events

        \(describeRecentEvents(events.suffix(12), formatter: formatter))

        ## Privacy Notes

        This context was generated locally. It does not include raw screenshots, camera frames, video, audio, typed characters, or raw app text. Full-context mode sends content annotations and entity aggregates only.
        """
    }

    private func describePrimaryContext(_ event: ObserverEvent) -> String {
        switch event.type {
        case .contentContext:
            return compactLines([
                requiredLine("App", event.payload["app_name"] ?? event.appID ?? "unknown"),
                optionalLine("Kind", event.payload["content_kind"]),
                optionalLine("Topic", event.payload["topic"]),
                optionalLine("Sentiment", event.payload["sentiment"]),
                optionalLine("Entity", pseudonymizedEntity(event.payload["source_entity_id"])),
                optionalLine("Display", event.payload["display_role"])
            ])

        case .screenContext, .writingContext:
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

    private func describeWritingContexts(_ writingContexts: [ObserverEvent]) -> String {
        let contexts = writingContexts.suffix(4)
        guard !contexts.isEmpty else {
            return "- No active writing context captured yet."
        }

        return contexts.map { event in
            let app = event.payload["app_name"] ?? event.appID ?? "unknown"
            let window = event.payload["window_title"].map { " · \($0)" } ?? ""
            let text = event.payload["focused_element_value"]
                ?? event.payload["selected_text"]
                ?? ""
            return "- \(app)\(window) · writing: \(text)"
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
            let kind = event.payload["context_kind"].map { " · \($0)" } ?? ""
            return "- \(app)\(kind) · OCR: \(text)"
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
        let eye = latest.payload["eye_contact_candidate"].map { candidate in
            let score = latest.payload["eye_contact_score"].map { ", score \($0)" } ?? ""
            let source = latest.payload["eye_signal_source"].map { ", source \($0)" } ?? ""
            return " Eye contact candidate: \(candidate)\(score)\(source)."
        } ?? ""
        return "- Face: \(face), zone: \(zone), position: \(position), detected faces: \(count).\(eye)"
    }

    private func describeBehaviorCues(_ behaviorCueEvents: [ObserverEvent]) -> String {
        let cues = behaviorCueEvents.suffix(6)
        guard !cues.isEmpty else {
            return "- No behavior cues recorded yet."
        }

        return cues.map { event in
            let cue = event.payload["cue"] ?? "unknown"
            let interpretation = event.payload["interpretation"] ?? "unknown"
            let app = event.payload["app_name"].map { " · \($0)" } ?? ""
            let activity = event.payload["activity_insight"].map { " · \($0)" } ?? ""
            return "- \(cue): \(interpretation)\(app)\(activity)"
        }.joined(separator: "\n")
    }

    private func describeGazeCalibration(_ gazeCalibrationEvents: [ObserverEvent]) -> String {
        let samples = gazeCalibrationEvents.suffix(8)
        guard !samples.isEmpty else {
            return "- No gaze calibration samples recorded yet."
        }

        return samples.map { event in
            let source = event.payload["target_source"] ?? "unknown"
            let role = event.payload["target_display_role"] ?? "unknown_display"
            let assumption = event.payload["target_assumption"].map { " · \($0)" } ?? ""
            let yaw = event.payload["head_yaw"].map { " · yaw: \($0)" } ?? ""
            let app = event.payload["app_name"].map { " · \($0)" } ?? ""
            return "- \(source): target \(role)\(assumption)\(yaw)\(app)"
        }.joined(separator: "\n")
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

    private func describeActivityInsights(_ activityInsightEvents: [ObserverEvent]) -> String {
        let insights = activityInsightEvents.suffix(6)
        guard !insights.isEmpty else {
            return "- No activity insights recorded yet."
        }

        return insights.map { event in
            let insight = event.payload["insight"] ?? "unknown"
            let app = event.payload["app_name"].map { " · \($0)" } ?? ""
            let mouse = event.payload["mouse_display_role"].map { " · pointer: \($0)" } ?? ""
            return "- \(insight)\(app)\(mouse)"
        }.joined(separator: "\n")
    }

    private func describeMediaPlayback(_ mediaEvents: [ObserverEvent]) -> String {
        let events = mediaEvents.suffix(6)
        guard !events.isEmpty else {
            return "- No media playback changes recorded yet."
        }

        return events.map { event in
            let source = event.payload["source"] ?? "unknown"
            let state = event.payload["state"] ?? "unknown"
            let title = event.payload["title"].map { " · \($0)" } ?? ""
            let artist = event.payload["artist"].map { " · \($0)" } ?? ""
            let insight = event.payload["activity_insight"].map { " · while: \($0)" } ?? ""
            return "- \(source): \(state)\(title)\(artist)\(insight)"
        }.joined(separator: "\n")
    }

    private func describeMediaReactions(_ mediaReactionEvents: [ObserverEvent]) -> String {
        let events = mediaReactionEvents.suffix(6)
        guard !events.isEmpty else {
            return "- No media reactions recorded yet."
        }

        return events.map { event in
            let reaction = event.payload["reaction"] ?? "unknown"
            let preference = event.payload["preference"] ?? "unknown"
            let title = event.payload["previous_title"] ?? event.payload["current_title"] ?? "unknown track"
            let artist = event.payload["previous_artist"].map { " · \($0)" } ?? ""
            let note = event.payload["confounder"].map { " · caveat: \($0)" } ?? ""
            return "- \(reaction): \(preference) · \(title)\(artist)\(note)"
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

            if let mouseDisplayRole = lastInput.payload["mouse_display_role"], idle < 15 {
                observations.append("- Recent pointer activity is on the \(mouseDisplayRole) display; use this as a workspace-attention signal.")
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
            "- \(formatter.string(from: event.timestamp)) | \(event.type.rawValue) | \(event.safePayloadSummary)"
        }.joined(separator: "\n")
    }

    private func describeContentContexts(_ contentContexts: [ObserverEvent]) -> String {
        let contexts = contentContexts.suffix(8)
        guard !contexts.isEmpty else {
            return "- No semantic content context captured yet."
        }

        return contexts.map { event in
            let app = event.payload["app_name"] ?? event.appID ?? "unknown"
            let kind = event.payload["content_kind"] ?? "unknown"
            let topic = event.payload["topic"] ?? "unknown"
            let sentiment = event.payload["sentiment"] ?? "neutral"
            let entity = pseudonymizedEntity(event.payload["source_entity_id"]).map { " · entity: \($0)" } ?? ""
            return "- \(app) · \(kind) · \(topic) · sentiment: \(sentiment)\(entity)"
        }.joined(separator: "\n")
    }

    private func describeBoundReactions(_ boundReactions: [ObserverEvent]) -> String {
        let reactions = boundReactions.suffix(8)
        guard !reactions.isEmpty else {
            return "- No content-bound reactions recorded yet."
        }

        return reactions.map { event in
            let cue = event.payload["cue"] ?? "unknown"
            let topic = event.payload["topic"] ?? "unknown"
            let entity = pseudonymizedEntity(event.payload["entity_id"]).map { " · entity: \($0)" } ?? ""
            return "- \(cue) after \(topic)\(entity)"
        }.joined(separator: "\n")
    }

    private func describeEntityAggregates(_ aggregates: [String: [String: String]]) -> String {
        guard !aggregates.isEmpty else {
            return "- No entity aggregates yet."
        }

        return aggregates.sorted { $0.key < $1.key }.prefix(10).map { id, payload in
            let name = pseudonymizedEntity(id) ?? payload["display_name"] ?? id
            let kind = payload["kind"] ?? "entity"
            let count = payload["interaction_count"] ?? "0"
            let sentiment = payload["sentiment_average"] ?? "0.00"
            return "- \(name) · \(kind) · interactions: \(count) · sentiment_avg: \(sentiment)"
        }.joined(separator: "\n")
    }

    private func pseudonymizedEntity(_ id: String?) -> String? {
        guard let id, !id.isEmpty else {
            return nil
        }
        guard pseudonymizeEntities else {
            return entityAggregates[id]?["display_name"] ?? id
        }
        if id.hasPrefix("person_") {
            return "person_\(String(id.suffix(4)))"
        }
        if id.hasPrefix("channel_") {
            return "channel_\(String(id.suffix(4)))"
        }
        return "entity_\(String(id.suffix(4)))"
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
        case .offHours:
            return "off_hours"
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

    var safePayloadSummary: String {
        let blockedKeys: Set<String> = [
            "raw_fragment",
            "focused_element_value",
            "selected_text",
            "text",
            "request_body"
        ]
        let safePayload = payload.filter { !blockedKeys.contains($0.key) }
        if safePayload.isEmpty {
            return "no safe payload"
        }
        return safePayload
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }
}
