import Foundation

enum WorkActor: String, Codable {
    case user
    case codex
    case chatgpt
    case claude
    case gemini
    case localModel = "local_model"
    case automation
    case unknownAgent = "unknown_agent"
}

enum EngagementMode: String, Codable {
    case active
    case formulating
    case reviewing
    case supervising
    case delegatedForeground = "delegated_foreground"
    case delegatedBackground = "delegated_background"
    case waiting
    case passiveObservation = "passive_observation"
    case unknown
}

struct AgencyAttribution {
    let primaryActor: WorkActor
    let contributingActors: [WorkActor]
    let engagementMode: EngagementMode
    let userActiveSeconds: Double
    let userFormulatingSeconds: Double
    let userReviewingSeconds: Double
    let userSupervisingSeconds: Double
    let userWaitingSeconds: Double
    let delegatedForegroundSeconds: Double
    let delegatedBackgroundSeconds: Double
    let attentionShare: Double?
    let userInputShare: Double?
    let autonomousChangeScore: Double?
    let confidence: Double
    let evidenceIds: [UUID]
    let reasonCodes: [String]

    var userAttributableSeconds: Double {
        userActiveSeconds + userFormulatingSeconds + userReviewingSeconds + userSupervisingSeconds + userWaitingSeconds
    }

    var agentExecutionSeconds: Double {
        delegatedForegroundSeconds + delegatedBackgroundSeconds
    }
}

struct AgencyAttributionBuilder {
    func build(
        episode: ObserverEvent?,
        episodeEvents: [ObserverEvent],
        elapsedSeconds: Double,
        activeSeconds: Double
    ) -> AgencyAttribution {
        let text = ([episode?.payload["apps"], episode?.payload["topic"], episode?.payload["goal"], episode?.payload["dominant_context"]]
            + episodeEvents.flatMap { [$0.payload["app_name"], $0.payload["content_kind"], $0.payload["topic"], $0.payload["activity_kind"]] })
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        let actor = agentActor(in: text)
        let inputEvents = episodeEvents.filter { $0.type == .inputActivity || $0.type == .typingRhythm || $0.type == .mouseDynamics || $0.type == .clipboardRoute }
        let promptEvents = episodeEvents.filter { $0.type == .contentContext && $0.payload["content_kind"] == "prompt" }
        let focusEvents = episodeEvents.filter { $0.type == .appFocus || $0.type == .appFocusInterval }
        let screenChangeEvents = episodeEvents.filter { $0.type == .screenContext || $0.type == .ocrContext || $0.type == .artifactTransition }
        let evidenceIds = Array((episode.map { [$0.id] } ?? []) + episodeEvents.suffix(24).map(\.id))

        if let forced = forcedAttribution(episode: episode, elapsedSeconds: elapsedSeconds, activeSeconds: activeSeconds, actor: actor, evidenceIds: evidenceIds) {
            return forced
        }

        let hasAgent = actor != nil
        let hasMeaningfulInput = inputEvents.isEmpty == false || promptEvents.isEmpty == false
        let hasManualArtifactWork = text.contains("figma") || text.contains("xcode") || text.contains("source_file") || text.contains("code")
        let autonomousScore = autonomousChangeScore(screenChanges: screenChangeEvents.count, inputEvents: inputEvents.count, elapsedSeconds: elapsedSeconds)
        let inputShare = activeSeconds > 0 ? min(1, Double(inputEvents.count + promptEvents.count) / max(1, Double(inputEvents.count + promptEvents.count + screenChangeEvents.count))) : nil
        let attentionShare = focusEvents.isEmpty ? nil : min(1, Double(focusEvents.count) / max(1, Double(episodeEvents.count)))

        if hasAgent && promptEvents.isEmpty == false {
            return attribution(
                actor: .user,
                contributors: [actor].compactMap { $0 },
                mode: .formulating,
                userFormulating: activeSeconds,
                delegatedForeground: 0,
                delegatedBackground: max(0, elapsedSeconds - activeSeconds),
                attentionShare: attentionShare,
                inputShare: inputShare,
                autonomousScore: autonomousScore,
                confidence: 0.82,
                evidenceIds: evidenceIds,
                reasons: ["prompt_declares_intention", "user_input_to_agent"]
            )
        }

        if let actor, hasAgent && !hasMeaningfulInput && autonomousScore >= 0.55 {
            let supervising = min(activeSeconds, max(60, activeSeconds * 0.25))
            return attribution(
                actor: actor,
                contributors: [.user],
                mode: .delegatedBackground,
                userSupervising: supervising,
                delegatedForeground: 0,
                delegatedBackground: max(0, elapsedSeconds - supervising),
                attentionShare: attentionShare,
                inputShare: inputShare,
                autonomousScore: autonomousScore,
                confidence: 0.78,
                evidenceIds: evidenceIds,
                reasons: ["agent_output_without_user_input", "user_time_not_equal_elapsed_span"]
            )
        }

        if let actor, hasAgent && !hasMeaningfulInput {
            let supervising = min(activeSeconds, max(30, activeSeconds * 0.35))
            return attribution(
                actor: actor,
                contributors: [.user],
                mode: .supervising,
                userSupervising: supervising,
                delegatedForeground: max(0, activeSeconds - supervising),
                delegatedBackground: max(0, elapsedSeconds - activeSeconds),
                attentionShare: attentionShare,
                inputShare: inputShare,
                autonomousScore: autonomousScore,
                confidence: 0.68,
                evidenceIds: evidenceIds,
                reasons: ["agent_window_observed", "weak_user_input"]
            )
        }

        if hasManualArtifactWork && hasMeaningfulInput {
            return attribution(
                actor: .user,
                contributors: [actor].compactMap { $0 },
                mode: .active,
                userActive: activeSeconds,
                delegatedForeground: 0,
                delegatedBackground: max(0, elapsedSeconds - activeSeconds),
                attentionShare: attentionShare,
                inputShare: inputShare,
                autonomousScore: autonomousScore,
                confidence: 0.80,
                evidenceIds: evidenceIds,
                reasons: ["manual_artifact_interaction", "user_input_present"]
            )
        }

        if hasAgent {
            return attribution(
                actor: actor ?? .unknownAgent,
                contributors: [.user],
                mode: .reviewing,
                userReviewing: activeSeconds,
                delegatedForeground: 0,
                delegatedBackground: max(0, elapsedSeconds - activeSeconds),
                attentionShare: attentionShare,
                inputShare: inputShare,
                autonomousScore: autonomousScore,
                confidence: 0.58,
                evidenceIds: evidenceIds,
                reasons: ["agent_context_visible", "agency_needs_review"]
            )
        }

        return attribution(
            actor: .user,
            contributors: [],
            mode: hasMeaningfulInput ? .active : .reviewing,
            userActive: hasMeaningfulInput ? activeSeconds : 0,
            userReviewing: hasMeaningfulInput ? 0 : activeSeconds,
            delegatedForeground: 0,
            delegatedBackground: 0,
            attentionShare: attentionShare,
            inputShare: inputShare,
            autonomousScore: autonomousScore,
            confidence: hasMeaningfulInput ? 0.76 : 0.62,
            evidenceIds: evidenceIds,
            reasons: hasMeaningfulInput ? ["user_input_present"] : ["reading_or_reviewing_without_agent"]
        )
    }

    func applyFallback(to slice: ObserverEvent) -> AgencyAttribution {
        let active = Double(slice.payload["active_seconds"] ?? "") ?? 0
        let elapsed = Double(slice.payload["elapsed_seconds"] ?? "") ?? active
        let actor = WorkActor(rawValue: slice.payload["primary_actor"] ?? "") ?? .user
        let mode = EngagementMode(rawValue: slice.payload["engagement_mode"] ?? "") ?? .active
        if slice.payload["user_attributable_seconds"] != nil || slice.payload["delegated_background_seconds"] != nil {
            return attribution(
                actor: actor,
                contributors: parseActors(slice.payload["contributing_actors"]),
                mode: mode,
                userActive: Double(slice.payload["user_active_seconds"] ?? "") ?? 0,
                userFormulating: Double(slice.payload["user_formulating_seconds"] ?? "") ?? 0,
                userReviewing: Double(slice.payload["user_reviewing_seconds"] ?? "") ?? 0,
                userSupervising: Double(slice.payload["user_supervising_seconds"] ?? "") ?? 0,
                userWaiting: Double(slice.payload["user_waiting_seconds"] ?? "") ?? 0,
                delegatedForeground: Double(slice.payload["delegated_foreground_seconds"] ?? "") ?? 0,
                delegatedBackground: Double(slice.payload["delegated_background_seconds"] ?? "") ?? 0,
                attentionShare: Double(slice.payload["attention_share"] ?? ""),
                inputShare: Double(slice.payload["user_input_share"] ?? ""),
                autonomousScore: Double(slice.payload["autonomous_change_score"] ?? ""),
                confidence: Double(slice.payload["agency_confidence"] ?? "") ?? slice.confidence,
                evidenceIds: eventIDs(slice.payload["agency_evidence_ids"] ?? slice.payload["source_event_ids"]),
                reasons: parseList(slice.payload["agency_reason_codes"])
            )
        }
        let text = [slice.payload["activity_kind"], slice.payload["summary"], slice.payload["dominant_app"]]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        let inferredActor = agentActor(in: text)
        if let inferredActor {
            return attribution(
                actor: inferredActor,
                contributors: [.user],
                mode: .supervising,
                userSupervising: min(active, active * 0.35),
                delegatedForeground: max(0, active * 0.65),
                delegatedBackground: max(0, elapsed - active),
                attentionShare: nil,
                inputShare: nil,
                autonomousScore: nil,
                confidence: 0.45,
                evidenceIds: [slice.id],
                reasons: ["legacy_slice_agent_context_fallback"]
            )
        }
        return attribution(
            actor: .user,
            contributors: [],
            mode: .active,
            userActive: active,
            delegatedForeground: 0,
            delegatedBackground: 0,
            attentionShare: nil,
            inputShare: nil,
            autonomousScore: nil,
            confidence: slice.confidence,
            evidenceIds: [slice.id],
            reasons: ["legacy_slice_user_active_fallback"]
        )
    }

    private func forcedAttribution(
        episode: ObserverEvent?,
        elapsedSeconds: Double,
        activeSeconds: Double,
        actor: WorkActor?,
        evidenceIds: [UUID]
    ) -> AgencyAttribution? {
        guard let raw = episode?.payload["engagement_mode"], let mode = EngagementMode(rawValue: raw) else {
            return nil
        }
        let primary = WorkActor(rawValue: episode?.payload["primary_actor"] ?? "") ?? actor ?? .user
        switch mode {
        case .delegatedBackground:
            let supervising = min(activeSeconds, Double(episode?.payload["user_supervising_seconds"] ?? "") ?? 0)
            return attribution(actor: primary, contributors: [.user], mode: mode, userSupervising: supervising, delegatedForeground: 0, delegatedBackground: max(0, elapsedSeconds - supervising), attentionShare: nil, inputShare: nil, autonomousScore: 1, confidence: 0.92, evidenceIds: evidenceIds, reasons: ["explicit_agency_ground_truth"])
        case .supervising:
            let supervising = Double(episode?.payload["user_supervising_seconds"] ?? "") ?? min(activeSeconds, activeSeconds * 0.35)
            return attribution(actor: primary, contributors: [.user], mode: mode, userSupervising: supervising, delegatedForeground: max(0, activeSeconds - supervising), delegatedBackground: max(0, elapsedSeconds - activeSeconds), attentionShare: nil, inputShare: nil, autonomousScore: nil, confidence: 0.90, evidenceIds: evidenceIds, reasons: ["explicit_agency_ground_truth"])
        case .formulating:
            return attribution(actor: .user, contributors: [primary].filter { $0 != .user }, mode: mode, userFormulating: activeSeconds, delegatedForeground: 0, delegatedBackground: max(0, elapsedSeconds - activeSeconds), attentionShare: nil, inputShare: nil, autonomousScore: nil, confidence: 0.90, evidenceIds: evidenceIds, reasons: ["explicit_agency_ground_truth"])
        case .reviewing:
            return attribution(actor: .user, contributors: [primary].filter { $0 != .user }, mode: mode, userReviewing: activeSeconds, delegatedForeground: 0, delegatedBackground: max(0, elapsedSeconds - activeSeconds), attentionShare: nil, inputShare: nil, autonomousScore: nil, confidence: 0.90, evidenceIds: evidenceIds, reasons: ["explicit_agency_ground_truth"])
        default:
            return nil
        }
    }

    private func agentActor(in text: String) -> WorkActor? {
        if text.contains("codex") { return .codex }
        if text.contains("chatgpt") || text.contains("chat gpt") { return .chatgpt }
        if text.contains("claude") { return .claude }
        if text.contains("gemini") { return .gemini }
        if text.contains("ollama") || text.contains("local_model") { return .localModel }
        return nil
    }

    private func autonomousChangeScore(screenChanges: Int, inputEvents: Int, elapsedSeconds: Double) -> Double {
        guard screenChanges > 0 else { return 0 }
        let raw = Double(screenChanges) / Double(max(1, screenChanges + inputEvents))
        let durationBoost = min(0.2, elapsedSeconds / 3600)
        return min(1, raw + durationBoost)
    }

    private func attribution(
        actor: WorkActor,
        contributors: [WorkActor],
        mode: EngagementMode,
        userActive: Double = 0,
        userFormulating: Double = 0,
        userReviewing: Double = 0,
        userSupervising: Double = 0,
        userWaiting: Double = 0,
        delegatedForeground: Double,
        delegatedBackground: Double,
        attentionShare: Double?,
        inputShare: Double?,
        autonomousScore: Double?,
        confidence: Double,
        evidenceIds: [UUID],
        reasons: [String]
    ) -> AgencyAttribution {
        let uniqueContributors = Array(Set(contributors.filter { $0 != actor })).sorted { $0.rawValue < $1.rawValue }
        return AgencyAttribution(
            primaryActor: actor,
            contributingActors: uniqueContributors,
            engagementMode: mode,
            userActiveSeconds: max(0, userActive),
            userFormulatingSeconds: max(0, userFormulating),
            userReviewingSeconds: max(0, userReviewing),
            userSupervisingSeconds: max(0, userSupervising),
            userWaitingSeconds: max(0, userWaiting),
            delegatedForegroundSeconds: max(0, delegatedForeground),
            delegatedBackgroundSeconds: max(0, delegatedBackground),
            attentionShare: attentionShare,
            userInputShare: inputShare,
            autonomousChangeScore: autonomousScore,
            confidence: max(0, min(1, confidence)),
            evidenceIds: Array(Set(evidenceIds)),
            reasonCodes: reasons
        )
    }

    private func parseActors(_ value: String?) -> [WorkActor] {
        parseList(value).compactMap(WorkActor.init(rawValue:))
    }

    private func parseList(_ value: String?) -> [String] {
        (value ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func eventIDs(_ value: String?) -> [UUID] {
        parseList(value).compactMap(UUID.init(uuidString:))
    }
}
