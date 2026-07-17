import Foundation

enum ObservationChannel: String {
    case camera
    case gaze
    case presence
    case object
    case gesture
    case scene
    case input
    case application
    case screen
    case accessibility
    case ocr
    case content
    case clipboard
    case artifact
    case browser
    case chat
    case repository
    case document
    case media
    case call
    case notification
    case system
    case userFeedback = "user_feedback"
}

struct RawObservationView: Equatable {
    let id: UUID
    let timestamp: Date
    let endedAt: Date?
    let sessionId: String?
    let sourceChannel: ObservationChannel
    let observationType: String
    let semanticSummary: String?
    let confidence: Double
    let quality: Double
    let freshness: Double
    let sourceEventIds: [UUID]
    let modelName: String?
    let modelVersion: String?
    let pipelineVersion: String
    let createdAt: Date
}

struct ContextFabricBuildResult {
    let cameraEvidence: [[String: String]]
    let artifactIdentities: [[String: String]]
    let artifactTransitions: [[String: String]]
    let activityThreads: [[String: String]]
    let assignments: [[String: String]]
    let contextSlices: [[String: String]]
    let linkAudits: [[String: String]]
    let intentionAnchors: [[String: String]]
    let spanIntentionAssignments: [[String: String]]
    let chainLinks: [[String: String]]
}

struct ContextFabricBuilder {
    private let iso = ISO8601DateFormatter()

    func observations(from events: [ObserverEvent], now: Date = Date()) -> [RawObservationView] {
        events.compactMap { event in
            guard let channel = channel(for: event) else {
                return nil
            }
            return RawObservationView(
                id: event.id,
                timestamp: event.timestamp,
                endedAt: endedAt(for: event),
                sessionId: event.payload["session_id"],
                sourceChannel: channel,
                observationType: event.type.rawValue,
                semanticSummary: semanticSummary(for: event),
                confidence: event.confidence,
                quality: quality(for: event),
                freshness: max(0, now.timeIntervalSince(event.timestamp)),
                sourceEventIds: [event.id],
                modelName: event.payload["source_model"] ?? event.payload["model"],
                modelVersion: event.payload["model_version"] ?? event.payload["calibration_version"],
                pipelineVersion: event.payload["pipeline_version"] ?? ObserverPipeline.version,
                createdAt: event.timestamp
            )
        }
    }

    func cameraEvidencePayloads(from attentionEvent: ObserverEvent, now: Date = Date()) -> [[String: String]] {
        guard attentionEvent.type == .attention else {
            return []
        }

        var payloads: [[String: String]] = []
        let facePresent = attentionEvent.payload["face_present"] == "true"
        payloads.append(cameraPayload(
            label: facePresent ? "user_present" : "user_absent",
            evidenceType: "presence",
            confidence: attentionEvent.confidence,
            source: attentionEvent,
            now: now
        ))

        if attentionEvent.payload["eye_contact_candidate"] == "true" {
            payloads.append(cameraPayload(
                label: "screen_attention_candidate",
                evidenceType: "gaze",
                confidence: min(0.75, attentionEvent.confidence),
                source: attentionEvent,
                now: now
            ))
        }

        if attentionEvent.payload["yawn_candidate"] == "true" {
            payloads.append(cameraPayload(
                label: "hand_near_mouth",
                evidenceType: "gesture",
                confidence: 0.25,
                source: attentionEvent,
                now: now,
                reason: "mouth_open_proxy_only"
            ))
        }

        if attentionEvent.payload["face_position"] == "left" || attentionEvent.payload["face_position"] == "right" {
            payloads.append(cameraPayload(
                label: "repeated_head_turn",
                evidenceType: "posture",
                confidence: 0.35,
                source: attentionEvent,
                now: now
            ))
        }

        return payloads
    }

    func build(events: [ObserverEvent], now: Date = Date()) -> ContextFabricBuildResult {
        let episodes = events.filter { $0.type == .episode }
        let existingAssignments = Set(events.filter { $0.type == .episodeThreadAssignment }.compactMap { $0.payload["episode_event_id"] })
        let existingSlices = Set(events.filter { $0.type == .contextSlice }.compactMap { $0.payload["episode_event_id"] })
        let existingThreadKeys = Set(events.filter { $0.type == .activityThread }.compactMap { $0.payload["thread_key"] })
        let existingArtifactKeys = Set(events.filter { $0.type == .artifactIdentity }.compactMap { $0.payload["canonical_key"] })
        let existingTransitionKeys = Set(events.filter { $0.type == .artifactTransition }.compactMap { $0.payload["transition_key"] })

        var artifactPayloads: [[String: String]] = []
        var transitionPayloads: [[String: String]] = []
        var threadPayloads: [[String: String]] = []
        var assignmentPayloads: [[String: String]] = []
        var slicePayloads: [[String: String]] = []
        var auditPayloads: [[String: String]] = []
        var emittedThreadKeys = existingThreadKeys
        var emittedArtifactKeys = existingArtifactKeys
        var emittedTransitionKeys = existingTransitionKeys

        for episode in episodes {
            let episodeEvents = sourceEvents(for: episode, in: events)
            let artifacts = inferArtifacts(from: episode, events: episodeEvents)
            for artifact in artifacts where emittedArtifactKeys.contains(artifact["canonical_key"] ?? "") == false {
                artifactPayloads.append(artifact)
                if let key = artifact["canonical_key"] {
                    emittedArtifactKeys.insert(key)
                }
            }
            for transition in inferArtifactTransitions(for: episode, episodeEvents: episodeEvents) where emittedTransitionKeys.contains(transition["transition_key"] ?? "") == false {
                transitionPayloads.append(transition)
                if let key = transition["transition_key"] {
                    emittedTransitionKeys.insert(key)
                }
            }

            let assignment = assignThread(for: episode, episodeEvents: episodeEvents, artifacts: artifacts)
            if emittedThreadKeys.contains(assignment.thread["thread_key"] ?? "") == false {
                threadPayloads.append(assignment.thread)
                if let key = assignment.thread["thread_key"] {
                    emittedThreadKeys.insert(key)
                }
            }

            if existingAssignments.contains(episode.id.uuidString) == false {
                assignmentPayloads.append(assignment.assignment)
                auditPayloads.append(assignment.audit)
            }
            if existingSlices.contains(episode.id.uuidString) == false,
               let slice = contextSlice(for: episode, episodeEvents: episodeEvents, assignment: assignment.assignment) {
                slicePayloads.append(slice)
            }
        }

        let intentionAttribution = IntentionAttributionBuilder().build(events: events)

        return .init(
            cameraEvidence: [],
            artifactIdentities: artifactPayloads,
            artifactTransitions: transitionPayloads,
            activityThreads: threadPayloads,
            assignments: assignmentPayloads,
            contextSlices: slicePayloads,
            linkAudits: auditPayloads,
            intentionAnchors: intentionAttribution.anchors,
            spanIntentionAssignments: intentionAttribution.spanAssignments,
            chainLinks: intentionAttribution.chainLinks
        )
    }

    private func assignThread(
        for episode: ObserverEvent,
        episodeEvents: [ObserverEvent],
        artifacts: [[String: String]]
    ) -> (thread: [String: String], assignment: [String: String], audit: [String: String]) {
        let artifactKey = artifacts.first?["canonical_key"]
        let topic = normalizedTopic(episode.payload["topic"] ?? episode.payload["goal"] ?? episode.payload["dominant_context"] ?? "unknown")
        let kind = episode.payload["episode_kind"] ?? "mixed"
        let key: String
        let confidence: Double
        let reasons: [String]
        if let artifactKey {
            key = "artifact:\(artifactKey)"
            confidence = 0.86
            reasons = ["same_canonical_artifact", "episode_lineage"]
        } else if topic != "unknown" && topic.count >= 4 {
            key = "topic:\(topic)"
            confidence = 0.62
            reasons = ["same_topic", "episode_semantics"]
        } else {
            key = "unassigned:\(episode.id.uuidString)"
            confidence = 0.25
            reasons = ["insufficient_content"]
        }

        let threadID = StableContextID.uuidString(for: key)
        let assignmentID = StableContextID.uuidString(for: "assignment:\(episode.id.uuidString):\(threadID):v1")
        let isUnassigned = confidence < 0.45 || key.hasPrefix("unassigned:")
        let sourceIDs = sourceIDs(for: episode, fallback: episodeEvents)
        let threadName = generatedThreadName(topic: topic, kind: kind, artifacts: artifacts)
        let thread: [String: String] = [
            "activity_thread_id": threadID,
            "thread_key": key,
            "generated_name": threadName,
            "status": "active",
            "first_seen_at": episode.payload["start"] ?? iso.string(from: episode.timestamp),
            "last_seen_at": episode.payload["end"] ?? iso.string(from: episode.timestamp),
            "artifact_ids": artifacts.map { $0["artifact_id"] ?? "" }.filter { !$0.isEmpty }.joined(separator: ","),
            "confidence": String(format: "%.2f", max(0.45, confidence)),
            "shadow_mode": "true",
            "source_event_ids": sourceIDs,
            "pipeline_version": ObserverPipeline.version
        ]
        let assignment: [String: String] = [
            "assignment_id": assignmentID,
            "episode_event_id": episode.id.uuidString,
            "episode_payload_id": episode.payload["episode_id"] ?? episode.id.uuidString,
            "activity_thread_id": isUnassigned ? "" : threadID,
            "assignment_state": isUnassigned ? "unassigned" : "assigned",
            "confidence": String(format: "%.2f", confidence),
            "assigned_by": "context_linker_v0",
            "reason_codes": reasons.joined(separator: ","),
            "version": "1",
            "is_current": "true",
            "user_locked": "false",
            "source_event_ids": sourceIDs,
            "pipeline_version": ObserverPipeline.version
        ]
        let audit: [String: String] = [
            "episode_event_id": episode.id.uuidString,
            "activity_thread_id": isUnassigned ? "" : threadID,
            "decision": isUnassigned ? "left_unassigned" : "assigned",
            "reason_codes": reasons.joined(separator: ","),
            "confidence": String(format: "%.2f", confidence),
            "tracker_is_not_causal_truth": "true",
            "source_event_ids": sourceIDs,
            "pipeline_version": ObserverPipeline.version
        ]
        return (thread, assignment, audit)
    }

    private func contextSlice(
        for episode: ObserverEvent,
        episodeEvents: [ObserverEvent],
        assignment: [String: String]
    ) -> [String: String]? {
        guard let start = iso.date(from: episode.payload["start"] ?? ""),
              let end = iso.date(from: episode.payload["end"] ?? ""),
              end > start
        else {
            return nil
        }
        let elapsed = end.timeIntervalSince(start)
        let idleSeconds = episodeEvents
            .filter { $0.type == .breakpoint && $0.payload["reason"] == "input_pause" }
            .compactMap { Double($0.payload["seconds_since_any_input"] ?? "") }
            .reduce(0, +)
        let active = max(0, elapsed - min(elapsed, idleSeconds))
        let kind = activityKind(for: episode.payload["episode_kind"] ?? episode.payload["dominant_context"] ?? "unknown")
        let agency = AgencyAttributionBuilder().build(
            episode: episode,
            episodeEvents: episodeEvents,
            elapsedSeconds: elapsed,
            activeSeconds: active
        )
        var payload: [String: String] = [
            "context_slice_id": StableContextID.uuidString(for: "slice:\(episode.id.uuidString)"),
            "episode_event_id": episode.id.uuidString,
            "attention_span_id": latestSpanID(in: episodeEvents) ?? "",
            "started_at": iso.string(from: start),
            "ended_at": iso.string(from: end),
            "elapsed_seconds": String(format: "%.1f", elapsed),
            "active_seconds": String(format: "%.1f", active),
            "activity_thread_id": assignment["activity_thread_id"] ?? "",
            "assignment_state": assignment["assignment_state"] ?? "unassigned",
            "primary_app_id": episode.appID ?? "",
            "activity_kind": kind,
            "coverage": String(format: "%.2f", coverage(for: episodeEvents)),
            "double_count_guard": "episode_non_overlapping",
            "source_event_ids": sourceIDs(for: episode, fallback: episodeEvents),
            "pipeline_version": ObserverPipeline.version
        ]
        payload["primary_actor"] = agency.primaryActor.rawValue
        payload["contributing_actors"] = agency.contributingActors.map(\.rawValue).joined(separator: ",")
        payload["engagement_mode"] = agency.engagementMode.rawValue
        payload["user_active_seconds"] = String(format: "%.1f", agency.userActiveSeconds)
        payload["user_formulating_seconds"] = String(format: "%.1f", agency.userFormulatingSeconds)
        payload["user_reviewing_seconds"] = String(format: "%.1f", agency.userReviewingSeconds)
        payload["user_supervising_seconds"] = String(format: "%.1f", agency.userSupervisingSeconds)
        payload["user_waiting_seconds"] = String(format: "%.1f", agency.userWaitingSeconds)
        payload["user_attributable_seconds"] = String(format: "%.1f", agency.userAttributableSeconds)
        payload["delegated_foreground_seconds"] = String(format: "%.1f", agency.delegatedForegroundSeconds)
        payload["delegated_background_seconds"] = String(format: "%.1f", agency.delegatedBackgroundSeconds)
        payload["agent_execution_seconds"] = String(format: "%.1f", agency.agentExecutionSeconds)
        if let attentionShare = agency.attentionShare {
            payload["attention_share"] = String(format: "%.3f", attentionShare)
        }
        if let inputShare = agency.userInputShare {
            payload["user_input_share"] = String(format: "%.3f", inputShare)
        }
        if let autonomousScore = agency.autonomousChangeScore {
            payload["autonomous_change_score"] = String(format: "%.3f", autonomousScore)
        }
        payload["agency_confidence"] = String(format: "%.2f", agency.confidence)
        payload["agency_evidence_ids"] = agency.evidenceIds.map(\.uuidString).joined(separator: ",")
        payload["agency_reason_codes"] = agency.reasonCodes.joined(separator: ",")
        return payload
    }

    private func inferArtifacts(from episode: ObserverEvent, events: [ObserverEvent]) -> [[String: String]] {
        var artifacts: [[String: String]] = []
        for event in events where [.contentContext, .screenContext, .writingContext, .ocrContext, .appFocus].contains(event.type) {
            guard let identity = artifactIdentity(from: event) else {
                continue
            }
            artifacts.append(identity)
        }
        return uniquePayloads(artifacts, key: "canonical_key")
    }

    private func inferArtifactTransitions(for episode: ObserverEvent, episodeEvents: [ObserverEvent]) -> [[String: String]] {
        let sortedEvents = episodeEvents.sorted { $0.timestamp < $1.timestamp }
        let sourceEvents = sortedEvents.filter(isContextSourceEvent)
        guard sourceEvents.isEmpty == false else {
            return []
        }

        var transitions: [[String: String]] = []
        for target in sortedEvents {
            guard let artifact = artifactIdentity(from: target),
                  let artifactKind = artifact["kind"],
                  isOpenableArtifactKind(artifactKind)
            else {
                continue
            }

            let candidates = sourceEvents.compactMap { source -> (event: ObserverEvent, score: ArtifactTransitionScore)? in
                guard source.id != target.id,
                      source.timestamp <= target.timestamp,
                      target.timestamp.timeIntervalSince(source.timestamp) <= 45 * 60
                else {
                    return nil
                }
                let score = transitionScore(from: source, to: target, artifact: artifact)
                return score.confidence >= 0.42 ? (source, score) : nil
            }
            guard let best = candidates.max(by: { $0.score.confidence < $1.score.confidence }) else {
                continue
            }

            let transitionKey = "transition:\(best.event.id.uuidString):\(target.id.uuidString):\(artifact["canonical_key"] ?? "")"
            let sourceIDs = [episode.id.uuidString, best.event.id.uuidString, target.id.uuidString]
            var payload: [String: String] = [
                "artifact_transition_id": StableContextID.uuidString(for: transitionKey),
                "transition_key": transitionKey,
                "episode_event_id": episode.id.uuidString,
                "episode_payload_id": episode.payload["episode_id"] ?? episode.id.uuidString,
                "from_event_id": best.event.id.uuidString,
                "to_event_id": target.id.uuidString,
                "to_artifact_id": artifact["artifact_id"] ?? "",
                "to_artifact_kind": artifactKind,
                "to_artifact_key": artifact["canonical_key"] ?? "",
                "artifact_label": safeDisplayName(artifact["display_name"] ?? ""),
                "opened_after_seconds": String(format: "%.1f", target.timestamp.timeIntervalSince(best.event.timestamp)),
                "inferred_reason": best.score.inferredReason,
                "reason_codes": best.score.reasonCodes.joined(separator: ","),
                "confidence": String(format: "%.2f", best.score.confidence),
                "shadow_mode": "true",
                "source_event_ids": sourceIDs.joined(separator: ","),
                "evidence_event_ids": sourceIDs.joined(separator: ","),
                "pipeline_version": ObserverPipeline.version
            ]
            if let sourceLabel = contextSourceLabel(for: best.event) {
                payload["source_context_label"] = sourceLabel
            }
            if let issueKey = best.score.sharedIdentifiers.first {
                payload["shared_identifier"] = issueKey
            }
            transitions.append(payload)
        }
        return uniquePayloads(transitions, key: "transition_key")
    }

    private func artifactIdentity(from event: ObserverEvent) -> [String: String]? {
        let app = event.payload["app_name"] ?? event.appID ?? ""
        let title = event.payload["window_title"] ?? event.payload["document_title"] ?? event.payload["title"] ?? event.payload["topic"] ?? ""
        let safeTitle = safeDisplayName(title)
        let thread = event.payload["source_entity_id"] ?? event.payload["source_entity_display_name"] ?? event.payload["source_entity"] ?? ""
        let urlHash = event.payload["url_hash"] ?? event.payload["stable_url_hash"] ?? ""
        let combined = "\(app) \(title) \(event.payload["url_host"] ?? "") \(event.payload["url_path"] ?? "")"
        let kind: String
        let key: String
        if let issueKey = issueIdentifiers(in: combined).first {
            kind = "jira_issue"
            key = "jira:\(issueKey)"
        } else if app.lowercased().contains("figma") || title.lowercased().contains("figma") {
            kind = "figma_file"
            key = "figma:\(title.isEmpty ? app : safeTitle)"
        } else if ["message", "email"].contains(event.payload["content_kind"]) || !thread.isEmpty {
            kind = event.payload["content_kind"] == "email" ? "email_thread" : "chat_thread"
            key = "\(kind):\(thread.isEmpty ? safeTitle : PrivacyRedactor.redact(thread))"
        } else if !urlHash.isEmpty {
            kind = "browser_page"
            key = "url:\(urlHash)"
        } else if event.payload["file_path_hash"]?.isEmpty == false || event.payload["document_id"]?.isEmpty == false {
            kind = "document"
            key = "document:\(event.payload["file_path_hash"] ?? event.payload["document_id"] ?? safeTitle)"
        } else if isBrowserApp(app), !title.isEmpty {
            kind = "browser_page"
            key = "browser:\(safeTitle)"
        } else if !title.isEmpty {
            kind = "browser_document"
            key = "\(app):\(safeTitle)"
        } else {
            return nil
        }
        var payload = artifactPayload(
            kind: kind,
            canonicalKey: key,
            displayName: title.isEmpty ? app : safeTitle,
            sourceApp: app,
            sourceIDs: event.id.uuidString
        )
        // Resource URLs have already been scrubbed at capture time. They are a
        // local navigation aid for the task tree, not model input.
        if let resourceURL = event.payload["resource_url"], !resourceURL.isEmpty {
            payload["resource_url"] = resourceURL
            payload["resource_domain"] = event.payload["resource_domain"] ?? ""
        }
        return payload
    }

    private func artifactPayload(kind: String, canonicalKey: String, displayName: String, sourceApp: String?, sourceIDs: String) -> [String: String] {
        [
            "artifact_id": StableContextID.uuidString(for: canonicalKey),
            "kind": kind,
            "canonical_key": canonicalKey,
            "display_name": displayName,
            "source_app": sourceApp ?? "",
            "first_seen_at": iso.string(from: Date()),
            "last_seen_at": iso.string(from: Date()),
            "source_event_ids": sourceIDs,
            "pipeline_version": ObserverPipeline.version
        ]
    }

    private func cameraPayload(
        label: String,
        evidenceType: String,
        confidence: Double,
        source: ObserverEvent,
        now: Date,
        reason: String? = nil
    ) -> [String: String] {
        var payload = [
            "camera_evidence_id": StableContextID.uuidString(for: "camera:\(source.id.uuidString):\(label)"),
            "evidence_type": evidenceType,
            "label": label,
            "confidence": String(format: "%.2f", confidence),
            "quality": String(format: "%.2f", quality(for: source)),
            "freshness_seconds": String(format: "%.1f", now.timeIntervalSince(source.timestamp)),
            "persistence_seconds": "0.0",
            "source_model": "local_vision",
            "model_version": source.payload["calibration_version"] ?? "camera-evidence-v0",
            "shadow_mode": "true",
            "candidate": label.hasSuffix("_candidate") ? "true" : "false",
            "source_event_ids": source.id.uuidString,
            "pipeline_version": ObserverPipeline.version
        ]
        if let reason {
            payload["reason_code"] = reason
        }
        return payload
    }

    private func sourceEvents(for episode: ObserverEvent, in events: [ObserverEvent]) -> [ObserverEvent] {
        let ids = (episode.payload["trace_event_ids"] ?? episode.payload["source_event_ids"] ?? "")
            .split(separator: ",")
            .map(String.init)
        // Persisted event batches can briefly contain the same event twice while a
        // session is being closed. Keep the freshest copy instead of trapping.
        let byID = events.reduce(into: [String: ObserverEvent]()) { index, event in
            let key = event.id.uuidString
            if let existing = index[key], existing.timestamp > event.timestamp {
                return
            }
            index[key] = event
        }
        let resolved = ids.compactMap { byID[$0] }
        if !resolved.isEmpty {
            return resolved
        }
        guard let start = iso.date(from: episode.payload["start"] ?? ""),
              let end = iso.date(from: episode.payload["end"] ?? "")
        else {
            return []
        }
        return events.filter { $0.timestamp >= start && $0.timestamp <= end && $0.id != episode.id }
    }

    private func sourceIDs(for episode: ObserverEvent, fallback: [ObserverEvent]) -> String {
        let explicit = episode.payload["trace_event_ids"] ?? episode.payload["source_event_ids"] ?? ""
        if explicit.isEmpty == false {
            return explicit
        }
        return fallback.map(\.id.uuidString).joined(separator: ",")
    }

    private func channel(for event: ObserverEvent) -> ObservationChannel? {
        switch event.type {
        case .attention, .cameraAttentionStarted, .cameraAttentionStopped, .cameraPermission, .cameraEvidence:
            return .camera
        case .gazeCalibrationSample:
            return .gaze
        case .awayPresenceIncident, .securityIncident:
            return .presence
        case .inputActivity, .typingRhythm, .mouseDynamics, .scrollProfile:
            return .input
        case .appFocus, .appFocusInterval, .attentionSpan:
            return .application
        case .screenContext:
            return .screen
        case .writingContext:
            return .accessibility
        case .ocrContext:
            return .ocr
        case .contentContext:
            return .content
        case .clipboardRoute:
            return .clipboard
        case .artifactIdentity:
            return .artifact
        case .artifactTransition:
            return .artifact
        case .mediaPlayback, .mediaReaction:
            return .media
        case .userLabel, .contextLinkUserLabel, .userNote:
            return .userFeedback
        case .displayInventory, .workspaceTopologyLoaded, .observingStarted, .observingPaused, .sessionBoundary, .observationGap:
            return .system
        default:
            return nil
        }
    }

    private func endedAt(for event: ObserverEvent) -> Date? {
        if let value = event.payload["end"] ?? event.payload["ended_at"] {
            return iso.date(from: value)
        }
        return nil
    }

    private func semanticSummary(for event: ObserverEvent) -> String? {
        event.payload["topic"]
            ?? event.payload["summary"]
            ?? event.payload["interpretation"]
            ?? event.payload["label"]
            ?? event.payload["app_name"]
    }

    private func quality(for event: ObserverEvent) -> Double {
        if let value = Double(event.payload["quality"] ?? "") {
            return value
        }
        if event.type == .attention, event.payload["face_present"] != "true" {
            return min(0.6, event.confidence)
        }
        if event.type == .contentContext, event.payload["topic"]?.isEmpty != false {
            return 0.45
        }
        return min(1, max(0.1, event.confidence))
    }

    private func normalizedTopic(_ value: String) -> String {
        let lowered = value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard lowered.isEmpty == false else {
            return "unknown"
        }
        return lowered
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(8)
            .joined(separator: "-")
    }

    private func generatedThreadName(topic: String, kind: String, artifacts: [[String: String]]) -> String {
        if let artifact = artifacts.first?["display_name"], artifact.isEmpty == false {
            return "\(readableKind(kind)) — \(safeDisplayName(artifact).prefix(80))"
        }
        if topic != "unknown" {
            return "\(readableKind(kind)) — \(safeDisplayName(topic.replacingOccurrences(of: "-", with: " ")).prefix(80))"
        }
        return readableKind(kind)
    }

    private func safeDisplayName(_ value: String) -> String {
        let withoutSecretTokens = PrivacyRedactor.redact(value)
            .replacingOccurrences(of: #"\[secret:[^\]]+\]"#, with: "[secret]", options: .regularExpression)
            .replacingOccurrences(of: #"https?://\S+"#, with: "[url]", options: .regularExpression)
            .replacingOccurrences(of: #"chatgpt\.com/c/\S+"#, with: "ChatGPT thread", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bpassword\b(\s+\S+){0,5}"#, with: "[sensitive topic]", options: .regularExpression)
        let collapsed = withoutSecretTokens
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? "unnamed artifact" : collapsed
    }

    private func readableKind(_ kind: String) -> String {
        switch kind {
        case "ai_assisted_work":
            return "AI-assisted work"
        case "ai_assisted_design":
            return "AI + design"
        case "design_work":
            return "Design"
        case "communication":
            return "Communication"
        case "reading_research":
            return "Research"
        default:
            return "Work context"
        }
    }

    private func activityKind(for episodeKind: String) -> String {
        switch episodeKind {
        case "ai_assisted_work", "ai_assisted_design":
            return "ai_assisted"
        case "design_work":
            return "design"
        case "communication":
            return "communication"
        case "reading_research":
            return "research"
        case "admin":
            return "administration"
        default:
            return "unknown"
        }
    }

    private func latestSpanID(in events: [ObserverEvent]) -> String? {
        events.reversed().first { $0.type == .attentionSpan }?.id.uuidString
    }

    private func coverage(for events: [ObserverEvent]) -> Double {
        let groups = Set(events.compactMap { channel(for: $0)?.rawValue })
        return min(1, Double(groups.count) / 5.0)
    }

    private func uniquePayloads(_ payloads: [[String: String]], key: String) -> [[String: String]] {
        var seen = Set<String>()
        return payloads.filter { payload in
            guard let value = payload[key], !seen.contains(value) else {
                return false
            }
            seen.insert(value)
            return true
        }
    }

    private struct ArtifactTransitionScore {
        let confidence: Double
        let reasonCodes: [String]
        let inferredReason: String
        let sharedIdentifiers: [String]
    }

    private func isContextSourceEvent(_ event: ObserverEvent) -> Bool {
        let app = (event.payload["app_name"] ?? event.appID ?? "").lowercased()
        let kind = event.payload["content_kind"] ?? ""
        if ["message", "email", "prompt"].contains(kind) {
            return true
        }
        if event.payload["source_entity_id"]?.isEmpty == false ||
            event.payload["source_entity_display_name"]?.isEmpty == false ||
            event.payload["source_entity"]?.isEmpty == false {
            return true
        }
        return ["telegram", "whatsapp", "viber", "gmail", "inbox", "chatgpt", "claude", "slack", "teams"]
            .contains { app.contains($0) }
    }

    private func isOpenableArtifactKind(_ kind: String) -> Bool {
        ["jira_issue", "figma_file", "browser_page", "browser_document", "document"].contains(kind)
    }

    private func isBrowserApp(_ app: String) -> Bool {
        let lowered = app.lowercased()
        return ["chrome", "safari", "arc", "browser", "brave", "edge", "firefox"].contains { lowered.contains($0) }
    }

    private func transitionScore(from source: ObserverEvent, to target: ObserverEvent, artifact: [String: String]) -> ArtifactTransitionScore {
        let delay = target.timestamp.timeIntervalSince(source.timestamp)
        var score = 0.18
        var reasons = ["opened_after_context"]

        if delay <= 10 * 60 {
            score += 0.16
            reasons.append("short_time_distance")
        } else {
            score += 0.08
        }

        let sourceText = semanticText(for: source)
        let targetText = semanticText(for: target) + " " + (artifact["display_name"] ?? "") + " " + (artifact["canonical_key"] ?? "")
        let sharedIDs = Array(Set(issueIdentifiers(in: sourceText)).intersection(Set(issueIdentifiers(in: targetText)))).sorted()
        if sharedIDs.isEmpty == false {
            score += 0.42
            reasons.append("shared_artifact_identifier")
        }

        let overlap = tokenOverlap(sourceText, targetText)
        if overlap.count >= 2 {
            score += min(0.28, Double(overlap.count) * 0.07)
            reasons.append("shared_topic_terms")
        }

        if isContextSourceEvent(source) {
            score += 0.06
            reasons.append("communication_or_prompt_source")
        }

        let inferredReason: String
        if sharedIDs.isEmpty == false {
            inferredReason = "opened_artifact_from_prior_context"
        } else if overlap.count >= 2 {
            inferredReason = "opened_related_link_or_file_after_context"
        } else {
            inferredReason = "opened_after_recent_context"
        }

        return ArtifactTransitionScore(
            confidence: min(0.92, score),
            reasonCodes: Array(Set(reasons)).sorted(),
            inferredReason: inferredReason,
            sharedIdentifiers: sharedIDs
        )
    }

    private func semanticText(for event: ObserverEvent) -> String {
        [
            event.payload["topic"],
            event.payload["goal"],
            event.payload["summary"],
            event.payload["interpretation"],
            event.payload["window_title"],
            event.payload["document_title"],
            event.payload["title"],
            event.payload["app_name"],
            event.payload["content_kind"],
            event.payload["source_entity_display_name"],
            event.payload["source_entity"],
            event.payload["url_host"],
            event.payload["url_path"]
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    private func contextSourceLabel(for event: ObserverEvent) -> String? {
        let entity = event.payload["source_entity_display_name"] ?? event.payload["source_entity"] ?? event.payload["source_entity_id"]
        let topic = event.payload["topic"] ?? event.payload["summary"] ?? event.payload["window_title"]
        let label = [entity, topic]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return label.isEmpty ? nil : safeDisplayName(label)
    }

    private func issueIdentifiers(in value: String) -> [String] {
        let pattern = #"\b[A-Z][A-Z0-9]+-\d+\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let uppercased = value.uppercased()
        let nsRange = NSRange(uppercased.startIndex..<uppercased.endIndex, in: uppercased)
        return regex.matches(in: uppercased, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: uppercased) else {
                return nil
            }
            return String(uppercased[range])
        }
    }

    private func tokenOverlap(_ lhs: String, _ rhs: String) -> Set<String> {
        tokens(in: lhs).intersection(tokens(in: rhs))
    }

    private func tokens(in value: String) -> Set<String> {
        let stopwords: Set<String> = [
            "with", "from", "that", "this", "page", "https", "http", "www", "com",
            "google", "chrome", "safari", "figma", "jira", "open", "opened",
            "and", "the", "for", "you", "your", "что", "это", "как", "для", "или",
            "уже", "надо", "нужно", "там", "тут", "страница", "окно"
        ]
        return Set(value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && stopwords.contains($0) == false })
    }
}

enum StableContextID {
    static func uuidString(for key: String) -> String {
        let bytes = Array(key.utf8)
        var hash1: UInt64 = 0xcbf29ce484222325
        var hash2: UInt64 = 0x9e3779b97f4a7c15
        for byte in bytes {
            hash1 ^= UInt64(byte)
            hash1 &*= 0x100000001b3
            hash2 ^= (UInt64(byte) &+ 0x9e3779b97f4a7c15 &+ (hash2 << 6) &+ (hash2 >> 2))
        }
        var uuidBytes = Array(repeating: UInt8(0), count: 16)
        withUnsafeBytes(of: hash1.bigEndian) { buffer in
            for index in 0..<8 {
                uuidBytes[index] = buffer[index]
            }
        }
        withUnsafeBytes(of: hash2.bigEndian) { buffer in
            for index in 0..<8 {
                uuidBytes[index + 8] = buffer[index]
            }
        }
        uuidBytes[6] = (uuidBytes[6] & 0x0F) | 0x50
        uuidBytes[8] = (uuidBytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        )).uuidString
    }
}
