import Foundation

struct CognitiveStateDecision: Equatable {
    let state: String
    let confidence: Double
    let reason: String
    let evidenceEventIDs: [String]
    let payload: [String: String]
}

struct CognitiveStateEvaluator {
    let settings: ObserverSettings.CognitiveSettings

    func evaluate(events: [ObserverEvent], now: Date = Date()) -> CognitiveStateDecision? {
        let recent = events.filter { now.timeIntervalSince($0.timestamp) <= max(settings.avoidanceWindowSeconds, settings.flowMinimumSeconds) }
        let latestInput = recent.last { $0.type == .inputActivity }
        let latestAttention = recent.last { $0.type == .attention }
        let latestFocus = recent.last { $0.type == .appFocus }

        if let away = awayState(latestInput: latestInput, latestAttention: latestAttention) {
            return away
        }

        if let avoidance = avoidanceState(events: recent) {
            return avoidance
        }

        if let overload = overloadState(events: recent) {
            return overload
        }

        if let flow = flowState(events: recent, latestInput: latestInput, latestFocus: latestFocus, now: now) {
            return flow
        }

        if let wandering = wanderingState(events: recent, latestInput: latestInput, latestAttention: latestAttention, now: now) {
            return wandering
        }

        if let reading = readingState(latestInput: latestInput, latestAttention: latestAttention, latestFocus: latestFocus) {
            return reading
        }

        if let input = latestInput,
           let idle = Double(input.payload["seconds_since_any_input"] ?? ""),
           idle < settings.readingIdleSeconds {
            return decision(
                state: "engaged",
                confidence: 0.62,
                reason: "recent_input",
                evidence: [input.id.uuidString, latestFocus?.id.uuidString].compactMap { $0 },
                extra: ["seconds_since_any_input": String(format: "%.1f", idle)]
            )
        }

        return decision(
            state: "idle",
            confidence: 0.55,
            reason: "no_stronger_state",
            evidence: [latestInput?.id.uuidString, latestFocus?.id.uuidString].compactMap { $0 }
        )
    }

    private func awayState(
        latestInput: ObserverEvent?,
        latestAttention: ObserverEvent?
    ) -> CognitiveStateDecision? {
        guard latestAttention?.payload["face_present"] == "false",
              let idleText = latestInput?.payload["seconds_since_any_input"],
              let idle = Double(idleText),
              idle >= settings.awayIdleSeconds
        else {
            return nil
        }

        return decision(
            state: "away",
            confidence: 0.78,
            reason: "face_absent_and_input_idle",
            evidence: [latestAttention?.id.uuidString, latestInput?.id.uuidString].compactMap { $0 },
            extra: ["seconds_since_any_input": String(format: "%.1f", idle)]
        )
    }

    private func flowState(
        events: [ObserverEvent],
        latestInput: ObserverEvent?,
        latestFocus: ObserverEvent?,
        now: Date
    ) -> CognitiveStateDecision? {
        guard let latestInput,
              let idle = Double(latestInput.payload["seconds_since_any_input"] ?? ""),
              idle <= settings.activeInputMaximumIdleSeconds,
              let latestFocus,
              let appName = latestFocus.payload["app_name"]
        else {
            return nil
        }

        let windowStart = now.addingTimeInterval(-settings.flowMinimumSeconds)
        let focusEvents = events.filter { $0.type == .appFocus && $0.timestamp >= windowStart }
        let uniqueApps = Set(focusEvents.compactMap { $0.payload["app_name"] })
        guard uniqueApps.count <= 1 || (uniqueApps.count == 1 && uniqueApps.contains(appName)) else {
            return nil
        }

        let inputEvents = events.filter { $0.type == .inputActivity && $0.timestamp >= windowStart }
        guard inputEvents.count >= 3,
              inputEvents.allSatisfy({ (Double($0.payload["seconds_since_any_input"] ?? "") ?? .greatestFiniteMagnitude) <= settings.activeInputMaximumIdleSeconds })
        else {
            return nil
        }

        return decision(
            state: "flow",
            confidence: 0.68,
            reason: "stable_single_context_input",
            evidence: (inputEvents.suffix(4) + [latestFocus]).map { $0.id.uuidString },
            extra: [
                "app_name": appName,
                "missing_evidence": "burst_variance_and_blink_baseline"
            ]
        )
    }

    private func overloadState(events: [ObserverEvent]) -> CognitiveStateDecision? {
        let recentCues = events.suffix(80).filter { $0.type == .behaviorCue || $0.type == .boundReaction }
        guard let cue = recentCues.last(where: { event in
            let text = [event.payload["cue"], event.payload["interpretation"], event.payload["sentiment"]]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
            return text.contains("friction")
                || text.contains("strong_reaction")
                || text.contains("frustrated")
                || text.contains("neg")
        }) else {
            return nil
        }

        return decision(
            state: "overload",
            confidence: 0.50,
            reason: "friction_or_negative_bound_reaction",
            evidence: [cue.id.uuidString],
            extra: ["missing_evidence": "deletion_ratio_au4_hover_hesitation"]
        )
    }

    private func wanderingState(
        events: [ObserverEvent],
        latestInput: ObserverEvent?,
        latestAttention: ObserverEvent?,
        now: Date
    ) -> CognitiveStateDecision? {
        guard latestAttention?.payload["face_present"] == "true",
              let latestInput,
              let idle = Double(latestInput.payload["seconds_since_any_input"] ?? ""),
              idle >= settings.wanderingIdleSeconds
        else {
            return nil
        }

        let contextChanged = events.contains { event in
            [.contentContext, .screenContext, .writingContext, .ocrContext, .appFocus].contains(event.type)
                && now.timeIntervalSince(event.timestamp) <= settings.wanderingIdleSeconds
        }
        guard !contextChanged else {
            return nil
        }

        return decision(
            state: "wandering",
            confidence: 0.48,
            reason: "idle_face_present_static_context_proxy",
            evidence: [latestInput.id.uuidString, latestAttention?.id.uuidString].compactMap { $0 },
            extra: ["missing_evidence": "screen_diff_and_reading_micro_motion_profile"]
        )
    }

    private func readingState(
        latestInput: ObserverEvent?,
        latestAttention: ObserverEvent?,
        latestFocus: ObserverEvent?
    ) -> CognitiveStateDecision? {
        guard latestAttention?.payload["face_present"] == "true",
              let latestInput,
              let idle = Double(latestInput.payload["seconds_since_any_input"] ?? ""),
              idle >= settings.readingIdleSeconds
        else {
            return nil
        }

        return decision(
            state: "reading",
            confidence: 0.61,
            reason: "face_present_input_pause",
            evidence: [latestInput.id.uuidString, latestAttention?.id.uuidString, latestFocus?.id.uuidString].compactMap { $0 },
            extra: ["seconds_since_any_input": String(format: "%.1f", idle)]
        )
    }

    private func avoidanceState(events: [ObserverEvent]) -> CognitiveStateDecision? {
        let focusIntervals = events.filter { $0.type == .appFocusInterval }
        guard focusIntervals.count >= settings.avoidanceCycles * 2 else {
            return nil
        }

        var cycles = 0
        var taskApp: String?
        var evidence: [String] = []

        for interval in focusIntervals {
            let app = interval.payload["app_name"] ?? "unknown"
            let duration = Double(interval.payload["duration_seconds"] ?? "") ?? 0
            if isTaskApp(app), duration < settings.taskFocusShortSeconds {
                taskApp = app
                evidence.append(interval.id.uuidString)
            } else if taskApp != nil, isFeedOrCommunication(app) {
                cycles += 1
                evidence.append(interval.id.uuidString)
            }
        }

        guard cycles >= settings.avoidanceCycles else {
            return nil
        }

        let latestContent = events.last { $0.type == .contentContext }
        return decision(
            state: "avoidance",
            confidence: 0.56,
            reason: "task_to_feed_return_cycles",
            evidence: Array(evidence.suffix(8)),
            extra: [
                "task_app": taskApp ?? "unknown",
                "cycle_count": "\(cycles)",
                "topic": latestContent?.payload["topic"] ?? "",
                "entity_id": latestContent?.payload["source_entity_id"] ?? ""
            ]
        )
    }

    private func isTaskApp(_ app: String) -> Bool {
        !isFeedOrCommunication(app)
    }

    private func isFeedOrCommunication(_ app: String) -> Bool {
        let lower = app.lowercased()
        return lower.contains("telegram")
            || lower.contains("whatsapp")
            || lower.contains("mail")
            || lower.contains("slack")
            || lower.contains("chrome")
            || lower.contains("safari")
    }

    private func decision(
        state: String,
        confidence: Double,
        reason: String,
        evidence: [String],
        extra: [String: String] = [:]
    ) -> CognitiveStateDecision {
        var payload: [String: String] = [
            "state": state,
            "reason": reason,
            "shadow_mode": "true",
            "evidence_event_ids": evidence.joined(separator: ",")
        ]
        extra.forEach { payload[$0.key] = $0.value }
        return CognitiveStateDecision(
            state: state,
            confidence: confidence,
            reason: reason,
            evidenceEventIDs: evidence,
            payload: payload
        )
    }
}
