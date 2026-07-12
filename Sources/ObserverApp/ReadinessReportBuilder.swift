import Foundation

struct FunnelReport {
    let payload: [String: String]
    let markdown: String
}

struct FusionAuditReport {
    let payload: [String: String]
    let markdown: String
}

struct ReadinessReport {
    let payload: [String: String]
    let markdown: String
    let isReadyForPrediction: Bool
}

struct ReadinessReportBuilder {
    let settings: ObserverSettings.ReadinessSettings
    var calendar: Calendar = .current

    func funnelReport(events: [ObserverEvent], now: Date = Date()) -> FunnelReport {
        let dayStart = calendar.startOfDay(for: now)
        let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart
        let today = events.filter { $0.timestamp >= dayStart }
        let rolling = events.filter { $0.timestamp >= sevenDayStart }
        let todayMetrics = funnelMetrics(events: today)
        let rollingMetrics = funnelMetrics(events: rolling)

        let payload = todayMetrics.payload(prefix: "today_")
            .merging(rollingMetrics.payload(prefix: "rolling_7d_")) { current, _ in current }
        let markdown = """
        ## Funnel Metrics

        | Window | Signals | Behavior | Fusion | State | Episode outcome | Bound reaction |
        | --- | ---: | ---: | ---: | ---: | ---: | ---: |
        | Today | \(todayMetrics.signals) | \(todayMetrics.behaviorCues) | \(todayMetrics.fusionHypotheses) | \(todayMetrics.cognitiveStates) | \(todayMetrics.episodeOutcomes) | \(todayMetrics.boundReactions) |
        | 7d | \(rollingMetrics.signals) | \(rollingMetrics.behaviorCues) | \(rollingMetrics.fusionHypotheses) | \(rollingMetrics.cognitiveStates) | \(rollingMetrics.episodeOutcomes) | \(rollingMetrics.boundReactions) |

        - Today conversion: \(todayMetrics.conversionSummary)
        - 7d conversion: \(rollingMetrics.conversionSummary)
        """

        return FunnelReport(payload: payload, markdown: markdown)
    }

    func fusionAudit(events: [ObserverEvent], now: Date = Date()) -> FusionAuditReport {
        let fusions = events
            .filter { $0.type == .fusionHypothesis }
            .suffix(settings.fusionAuditSampleSize)
        let audited = fusions.map { fusion in
            let evidenceIDs = Set((fusion.payload["evidence_event_ids"] ?? "")
                .split(separator: ",")
                .map(String.init))
            let candidateID = fusion.payload["candidate_event_id"]
            let evidence = events.filter { evidenceIDs.contains($0.id.uuidString) || $0.id.uuidString == candidateID }
            let channels = Set(evidence.compactMap(channel(for:)))
            return (fusion: fusion, channelCount: channels.count, channels: channels.sorted())
        }
        let passed = audited.filter { $0.channelCount >= 2 }.count
        let total = audited.count
        let passRate = total > 0 ? Double(passed) / Double(total) : 0
        let behaviorCount = max(1, events.filter { $0.type == .behaviorCue }.count)
        let fusionCount = events.filter { $0.type == .fusionHypothesis }.count
        let compression = Double(fusionCount) / Double(behaviorCount)
        let compressionOK = compression >= settings.fusionCompressionMinimum && compression <= settings.fusionCompressionMaximum
        let examples = audited.suffix(5).map { item in
            "- \(item.fusion.payload["cue"] ?? item.fusion.payload["interpretation"] ?? "fusion"): \(item.channels.joined(separator: "+"))"
        }.joined(separator: "\n")

        let payload: [String: String] = [
            "sample_size": "\(total)",
            "passed_two_channel_gate": "\(passed)",
            "pass_rate": String(format: "%.3f", passRate),
            "fusion_count": "\(fusionCount)",
            "behavior_cue_count": "\(behaviorCount)",
            "compression_ratio": String(format: "%.3f", compression),
            "compression_target": "\(settings.fusionCompressionMinimum)-\(settings.fusionCompressionMaximum)",
            "compression_ok": compressionOK ? "true" : "false"
        ]
        let markdown = """
        ## Fusion Audit

        - Sample: \(total) recent fusion hypotheses.
        - Real two-channel evidence: \(passed)/\(total) (\(Int(passRate * 100))%).
        - Compression fusion/behaviorCue: \(String(format: "%.2f", compression)) target \(settings.fusionCompressionMinimum)-\(settings.fusionCompressionMaximum).
        - Compression status: \(compressionOK ? "ok" : "needs rule fix").

        \(examples.isEmpty ? "- No fusion examples yet." : examples)
        """

        return FusionAuditReport(payload: payload, markdown: markdown)
    }

    func readinessReport(events: [ObserverEvent], now: Date = Date()) -> ReadinessReport {
        let cognitiveEvents = events.filter { $0.type == .cognitiveState }
        let cognitiveDays = Set(cognitiveEvents.map { calendar.startOfDay(for: $0.timestamp) }).count
        let boundReactionEvents = events.filter { $0.type == .boundReaction }
        let entitiesOrTopics = Set(boundReactionEvents.compactMap { event in
            event.payload["entity_id"] ?? event.payload["topic"]
        }).count
        let geminiEvents = events.filter { $0.type == .geminiInsight }
        let audit = fusionAudit(events: events, now: now)
        let cognitiveReady = cognitiveEvents.count >= settings.cognitiveStateMinimumEvents
            && cognitiveDays >= settings.cognitiveStateMinimumDays
        let boundReady = boundReactionEvents.count >= settings.boundReactionMinimumEvents
            && entitiesOrTopics >= settings.boundReactionMinimumEntitiesOrTopics
        let geminiReady = geminiEvents.count >= settings.geminiInsightMinimumEvents
        let fusionReady = audit.payload["compression_ok"] == "true"
        let ready = cognitiveReady && boundReady && geminiReady && fusionReady

        let blockers = [
            cognitiveReady ? nil : "cognitiveState: \(cognitiveEvents.count)/\(settings.cognitiveStateMinimumEvents), days \(cognitiveDays)/\(settings.cognitiveStateMinimumDays)",
            boundReady ? nil : "boundReaction: \(boundReactionEvents.count)/\(settings.boundReactionMinimumEvents), entity/topic \(entitiesOrTopics)/\(settings.boundReactionMinimumEntitiesOrTopics)",
            geminiReady ? nil : "geminiInsight: \(geminiEvents.count)/\(settings.geminiInsightMinimumEvents)",
            fusionReady ? nil : "fusion compression outside target"
        ].compactMap { $0 }

        let payload: [String: String] = [
            "status": ready ? "ready" : "not_ready",
            "cognitive_state_count": "\(cognitiveEvents.count)",
            "cognitive_state_days": "\(cognitiveDays)",
            "bound_reaction_count": "\(boundReactionEvents.count)",
            "bound_reaction_entities_or_topics": "\(entitiesOrTopics)",
            "gemini_insight_count": "\(geminiEvents.count)",
            "fusion_ready": fusionReady ? "true" : "false",
            "blockers": blockers.joined(separator: "; ")
        ]
        let markdown = """
        ## Prediction Readiness

        Status: \(ready ? "ready" : "not_ready")

        | Gate | Current | Target | Status |
        | --- | ---: | ---: | --- |
        | cognitiveState events | \(cognitiveEvents.count) | \(settings.cognitiveStateMinimumEvents) | \(cognitiveReady ? "ok" : "blocked") |
        | cognitiveState days | \(cognitiveDays) | \(settings.cognitiveStateMinimumDays) | \(cognitiveReady ? "ok" : "blocked") |
        | boundReaction events | \(boundReactionEvents.count) | \(settings.boundReactionMinimumEvents) | \(boundReady ? "ok" : "blocked") |
        | entity/topic coverage | \(entitiesOrTopics) | \(settings.boundReactionMinimumEntitiesOrTopics) | \(boundReady ? "ok" : "blocked") |
        | Gemini insights | \(geminiEvents.count) | \(settings.geminiInsightMinimumEvents) | \(geminiReady ? "ok" : "blocked") |
        | Fusion compression | \(audit.payload["compression_ratio"] ?? "?") | \(settings.fusionCompressionMinimum)-\(settings.fusionCompressionMaximum) | \(fusionReady ? "ok" : "blocked") |

        \(blockers.isEmpty ? "- No blockers." : blockers.map { "- \($0)" }.joined(separator: "\n"))
        """

        return ReadinessReport(payload: payload, markdown: markdown, isReadyForPrediction: ready)
    }

    private func funnelMetrics(events: [ObserverEvent]) -> FunnelMetrics {
        FunnelMetrics(
            signals: events.filter { [.attention, .inputActivity, .contentContext].contains($0.type) }.count,
            behaviorCues: events.filter { $0.type == .behaviorCue }.count,
            fusionHypotheses: events.filter { $0.type == .fusionHypothesis }.count,
            cognitiveStates: events.filter { $0.type == .cognitiveState }.count,
            episodeOutcomes: events.filter { $0.type == .episode && ($0.payload["outcome"]?.isEmpty == false) }.count,
            boundReactions: events.filter { $0.type == .boundReaction }.count
        )
    }

    private func channel(for event: ObserverEvent) -> String? {
        switch event.type {
        case .attention:
            return event.payload["face_present"] == "true" ? "camera" : nil
        case .behaviorCue:
            return behaviorCueChannel(event.payload)
        case .contentContext, .writingContext, .ocrContext, .screenContext:
            return "content"
        case .inputActivity, .typingRhythm, .mouseDynamics:
            return "input"
        case .scrollProfile:
            return "scroll"
        case .mediaPlayback, .mediaReaction:
            return "media"
        default:
            return nil
        }
    }

    private func behaviorCueChannel(_ payload: [String: String]) -> String {
        let cue = [payload["cue"], payload["interpretation"]]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        if cue.contains("smile")
            || cue.contains("posture")
            || cue.contains("concentration")
            || cue.contains("difficulty")
            || cue.contains("yawn")
            || cue.contains("energy_drop")
            || cue.contains("fatigue") {
            return "camera"
        }
        if cue.contains("writing") || cue.contains("text") || cue.contains("tone") {
            return "content"
        }
        if cue.contains("media") || cue.contains("music") {
            return "media"
        }
        return "input"
    }
}

private struct FunnelMetrics {
    let signals: Int
    let behaviorCues: Int
    let fusionHypotheses: Int
    let cognitiveStates: Int
    let episodeOutcomes: Int
    let boundReactions: Int

    var conversionSummary: String {
        [
            "behavior/signals \(ratio(behaviorCues, signals))",
            "fusion/behavior \(ratio(fusionHypotheses, behaviorCues))",
            "state/fusion \(ratio(cognitiveStates, fusionHypotheses))",
            "episode/state \(ratio(episodeOutcomes, cognitiveStates))",
            "reaction/episode \(ratio(boundReactions, episodeOutcomes))"
        ].joined(separator: ", ")
    }

    func payload(prefix: String) -> [String: String] {
        [
            "\(prefix)signals": "\(signals)",
            "\(prefix)behavior_cues": "\(behaviorCues)",
            "\(prefix)fusion_hypotheses": "\(fusionHypotheses)",
            "\(prefix)cognitive_states": "\(cognitiveStates)",
            "\(prefix)episode_outcomes": "\(episodeOutcomes)",
            "\(prefix)bound_reactions": "\(boundReactions)",
            "\(prefix)behavior_to_signals": ratioValue(behaviorCues, signals),
            "\(prefix)fusion_to_behavior": ratioValue(fusionHypotheses, behaviorCues),
            "\(prefix)state_to_fusion": ratioValue(cognitiveStates, fusionHypotheses),
            "\(prefix)episode_to_state": ratioValue(episodeOutcomes, cognitiveStates),
            "\(prefix)reaction_to_episode": ratioValue(boundReactions, episodeOutcomes)
        ]
    }

    private func ratio(_ numerator: Int, _ denominator: Int) -> String {
        guard denominator > 0 else {
            return "n/a"
        }
        return "\(Int((Double(numerator) / Double(denominator)) * 100))%"
    }

    private func ratioValue(_ numerator: Int, _ denominator: Int) -> String {
        guard denominator > 0 else {
            return "n/a"
        }
        return String(format: "%.3f", Double(numerator) / Double(denominator))
    }
}
