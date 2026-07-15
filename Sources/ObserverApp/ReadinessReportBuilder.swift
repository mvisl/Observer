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
        let todayMetrics = EpisodeReadinessMetrics(
            events: events.filter { $0.timestamp >= dayStart },
            calendar: calendar
        )
        let rollingMetrics = EpisodeReadinessMetrics(
            events: events.filter { $0.timestamp >= sevenDayStart },
            calendar: calendar
        )
        let todayIntentions = IntentionAttributionMetrics(events: events.filter { $0.timestamp >= dayStart })
        let rollingIntentions = IntentionAttributionMetrics(events: events.filter { $0.timestamp >= sevenDayStart })

        let payload = todayMetrics.payload(prefix: "today_")
            .merging(rollingMetrics.payload(prefix: "rolling_7d_")) { current, _ in current }
            .merging(todayIntentions.payload(prefix: "today_intention_")) { current, _ in current }
            .merging(rollingIntentions.payload(prefix: "rolling_7d_intention_")) { current, _ in current }
        let markdown = """
        ## Episode Readiness Funnel

        This is not a raw event-count conversion funnel. It measures whether episodes have enough lineage,
        fresh semantic context, and supported claims to become prediction material.

        | Window | Episodes | Days | Fresh content | Lineage | Unsupported claims |
        | --- | ---: | ---: | ---: | ---: | ---: |
        | Today | \(todayMetrics.episodes) | \(todayMetrics.independentDays) | \(todayMetrics.percent(todayMetrics.contentCoverage)) | \(todayMetrics.percent(todayMetrics.lineageCoverage)) | \(todayMetrics.percent(todayMetrics.unsupportedClaimRate)) |
        | 7d | \(rollingMetrics.episodes) | \(rollingMetrics.independentDays) | \(rollingMetrics.percent(rollingMetrics.contentCoverage)) | \(rollingMetrics.percent(rollingMetrics.lineageCoverage)) | \(rollingMetrics.percent(rollingMetrics.unsupportedClaimRate)) |

        ## Intention Attribution

        | Window | Prompt anchors | Current spans | Legacy spans | Task-linked spans | Coverage | Median span |
        | --- | ---: | ---: | ---: | ---: | ---: |
        | Today | \(todayIntentions.anchors) | \(todayIntentions.currentSpans) | \(todayIntentions.legacySpans) | \(todayIntentions.assignedSpans) | \(todayIntentions.percent(todayIntentions.coverage)) | \(todayIntentions.durationLabel) |
        | 7d | \(rollingIntentions.anchors) | \(rollingIntentions.currentSpans) | \(rollingIntentions.legacySpans) | \(rollingIntentions.assignedSpans) | \(rollingIntentions.percent(rollingIntentions.coverage)) | \(rollingIntentions.durationLabel) |

        Object presence: \(todayIntentions.objectPresenceStatus).
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
            "compression_note": "diagnostic_only_not_readiness_gate"
        ]
        let markdown = """
        ## Fusion Audit

        - Sample: \(total) recent fusion hypotheses.
        - Real two-channel evidence: \(passed)/\(total) (\(Int(passRate * 100))%).
        - Compression fusion/behaviorCue: \(String(format: "%.2f", compression)) diagnostic only, not a readiness target.

        \(examples.isEmpty ? "- No fusion examples yet." : examples)
        """

        return FusionAuditReport(payload: payload, markdown: markdown)
    }

    func readinessReport(events: [ObserverEvent], now: Date = Date()) -> ReadinessReport {
        let metrics = EpisodeReadinessMetrics(events: events, calendar: calendar)
        let cameraAB = CameraDetectorABReportBuilder().build(events: events)
        let evidenceEvents = events.filter { $0.type == .evidence }
        let situationModels = events.filter { $0.type == .situationModel }
        let interventionDecisions = events.filter { $0.type == .interventionDecision }
        let pipelineReady = metrics.lineageCoverage >= settings.minimumLineageCoverage
        let episodeReady = metrics.episodes >= settings.minimumIndependentEpisodes
            && metrics.independentDays >= settings.minimumEpisodeDays
            && metrics.contentCoverage >= settings.minimumEpisodeContentCoverage
        let semanticReady = metrics.unsupportedClaimRate <= settings.maximumUnsupportedClaimRate
            && !evidenceEvents.isEmpty
            && !situationModels.isEmpty
        let predictionReady = episodeReady
            && semanticReady
            && events.contains { $0.type == .prediction || $0.type == .interventionCandidate }
        let interventionReady = !interventionDecisions.isEmpty
        let userVisibleReady = pipelineReady && episodeReady && semanticReady && predictionReady && interventionReady
        let ready = pipelineReady && episodeReady && semanticReady && predictionReady

        let blockers = [
            pipelineReady ? nil : "pipeline integrity: lineage \(metrics.percent(metrics.lineageCoverage)) / \(metrics.percent(settings.minimumLineageCoverage))",
            episodeReady ? nil : "episode readiness: \(metrics.episodes)/\(settings.minimumIndependentEpisodes) episodes, \(metrics.independentDays)/\(settings.minimumEpisodeDays) days, content \(metrics.percent(metrics.contentCoverage))",
            semanticReady ? nil : "semantic readiness: evidence/situation model missing or unsupported claims \(metrics.percent(metrics.unsupportedClaimRate))",
            predictionReady ? nil : "prediction readiness: shadow predictions are not validated against episode outcomes",
            interventionReady ? nil : "intervention readiness: no intervention ledger outcomes yet",
            userVisibleReady ? nil : "user-visible readiness: strict gates not complete"
        ].compactMap { $0 }

        let payload: [String: String] = [
            "status": ready ? "ready" : "not_ready",
            "pipeline_integrity": pipelineReady ? "ready" : "not_ready",
            "episode_readiness": episodeReady ? "ready" : "not_ready",
            "semantic_readiness": semanticReady ? "ready" : "not_ready",
            "prediction_readiness": predictionReady ? "ready" : "not_ready",
            "intervention_readiness": interventionReady ? "ready" : "not_ready",
            "user_visible_readiness": userVisibleReady ? "ready" : "not_ready",
            "independent_episodes": "\(metrics.episodes)",
            "independent_episode_days": "\(metrics.independentDays)",
            "lineage_coverage": String(format: "%.3f", metrics.lineageCoverage),
            "episode_content_coverage": String(format: "%.3f", metrics.contentCoverage),
            "unsupported_claim_rate": String(format: "%.3f", metrics.unsupportedClaimRate),
            "camera_detector_ab_recommendation": cameraAB["recommendation"] ?? "keep_shadow",
            "blockers": blockers.joined(separator: "; ")
        ]
        let markdown = """
        ## Brain Readiness

        Status: \(ready ? "ready" : "not_ready")

        | Gate | Current | Target | Status |
        | --- | ---: | ---: | --- |
        | Pipeline integrity | \(metrics.percent(metrics.lineageCoverage)) | \(metrics.percent(settings.minimumLineageCoverage)) | \(pipelineReady ? "ok" : "blocked") |
        | Independent episodes | \(metrics.episodes) | \(settings.minimumIndependentEpisodes) | \(episodeReady ? "ok" : "blocked") |
        | Independent days | \(metrics.independentDays) | \(settings.minimumEpisodeDays) | \(episodeReady ? "ok" : "blocked") |
        | Episode content coverage | \(metrics.percent(metrics.contentCoverage)) | \(metrics.percent(settings.minimumEpisodeContentCoverage)) | \(episodeReady ? "ok" : "blocked") |
        | Unsupported claim rate | \(metrics.percent(metrics.unsupportedClaimRate)) | max \(metrics.percent(settings.maximumUnsupportedClaimRate)) | \(semanticReady ? "ok" : "blocked") |
        | Camera cascade A/B | \(cameraAB["cascade_precision"] ?? "0.000") precision / \(cameraAB["cascade_recall_proxy"] ?? "0.000") recall proxy | 14d labeled improvement | \(cameraAB["recommendation"] == "switch_after_full_window" ? "ok" : "shadow") |
        | Evidence graph | \(evidenceEvents.count) nodes | >0 | \(evidenceEvents.isEmpty ? "blocked" : "ok") |
        | Situation model | \(situationModels.count) models | >0 | \(situationModels.isEmpty ? "blocked" : "ok") |
        | Intervention ledger | \(interventionDecisions.count) decisions | >0 | \(interventionReady ? "ok" : "blocked") |

        \(blockers.isEmpty ? "- No blockers." : blockers.map { "- \($0)" }.joined(separator: "\n"))

        Gemini is treated as a hypothesis generator, not as ground truth.
        """

        return ReadinessReport(payload: payload, markdown: markdown, isReadyForPrediction: ready)
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
        case .objectPresence:
            return "object"
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

private struct IntentionAttributionMetrics {
    let events: [ObserverEvent]

    var anchors: Int { events.filter { $0.type == .intentionAnchor }.count }
    var spans: Int { events.filter { $0.type == .attentionSpan }.count }
    var currentSpans: Int {
        events.filter {
            $0.type == .attentionSpan
                && ($0.payload["segmentation"] ?? "").hasPrefix("attention_unit_v2_")
        }.count
    }
    var legacySpans: Int { spans - currentSpans }
    var assignedSpans: Int {
        Set(events.filter { $0.type == .spanIntentionAssignment }.compactMap { $0.payload["attention_span_id"] }).count
    }
    var coverage: Double { spans > 0 ? Double(assignedSpans) / Double(spans) : 0 }
    var objectPresenceStatus: String {
        let count = events.filter { $0.type == .objectPresence }.count
        return count == 0
            ? "camera visual classifier active; no supported object passed the confidence gate yet"
            : "\(count) shadow observations"
    }
    var durationLabel: String {
        let values = events
            .filter { $0.type == .attentionSpan }
            .compactMap { Double($0.payload["duration_seconds"] ?? "") }
            .sorted()
        guard values.isEmpty == false else { return "n/a" }
        let median = values[values.count / 2]
        return "\(Int(median / 60))m"
    }
    func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    func payload(prefix: String) -> [String: String] {
        [
            "\(prefix)anchors": "\(anchors)",
            "\(prefix)spans": "\(spans)",
            "\(prefix)current_spans": "\(currentSpans)",
            "\(prefix)legacy_spans": "\(legacySpans)",
            "\(prefix)assigned_spans": "\(assignedSpans)",
            "\(prefix)span_task_coverage": String(format: "%.3f", coverage),
            "\(prefix)median_span_seconds": durationLabel,
            "\(prefix)object_presence_status": objectPresenceStatus
        ]
    }
}

private struct EpisodeReadinessMetrics {
    let events: [ObserverEvent]
    let calendar: Calendar

    var episodes: Int {
        episodeEvents.count
    }

    var independentDays: Int {
        Set(episodeEvents.map { calendar.startOfDay(for: $0.timestamp) }).count
    }

    var lineageCoverage: Double {
        let derived = events.filter { $0.type.requiresLineage }
        guard !derived.isEmpty else {
            return 0
        }
        let complete = derived.filter { event in
            event.payload["pipeline_version"]?.isEmpty == false
                && event.payload["session_id"]?.isEmpty == false
                && event.payload["episode_id"]?.isEmpty == false
                && event.payload["source_event_ids"]?.isEmpty == false
        }
        return Double(complete.count) / Double(derived.count)
    }

    var contentCoverage: Double {
        guard !episodeEvents.isEmpty else {
            return 0
        }
        let covered = episodeEvents.filter { episode in
            guard let start = date(episode.payload["start"]),
                  let end = date(episode.payload["end"])
            else {
                return false
            }
            return events.contains { event in
                event.type == .contentContext
                    && event.timestamp >= start.addingTimeInterval(-90)
                    && event.timestamp <= end
            }
        }
        return Double(covered.count) / Double(episodeEvents.count)
    }

    var unsupportedClaimRate: Double {
        let candidates = events.filter { event in
            event.type == .geminiInsight
                || event.type == .fusionHypothesis
                || event.type == .situationModel
                || event.type == .interventionCandidate
        }
        guard !candidates.isEmpty else {
            return 1
        }
        let unsupported = candidates.filter { event in
            event.payload["source_event_ids"]?.isEmpty != false
                && event.payload["evidence_event_ids"]?.isEmpty != false
        }
        return Double(unsupported.count) / Double(candidates.count)
    }

    func payload(prefix: String) -> [String: String] {
        [
            "\(prefix)episodes": "\(episodes)",
            "\(prefix)independent_days": "\(independentDays)",
            "\(prefix)lineage_coverage": String(format: "%.3f", lineageCoverage),
            "\(prefix)content_coverage": String(format: "%.3f", contentCoverage),
            "\(prefix)unsupported_claim_rate": String(format: "%.3f", unsupportedClaimRate)
        ]
    }

    func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private var episodeEvents: [ObserverEvent] {
        events.filter { event in
            event.type == .episode && event.payload["outcome"]?.isEmpty == false
        }
    }

    private func date(_ value: String?) -> Date? {
        guard let value else {
            return nil
        }
        return ISO8601DateFormatter().date(from: value)
    }
}
