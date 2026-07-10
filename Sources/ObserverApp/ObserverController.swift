import AppKit
import Foundation

@MainActor
final class ObserverController {
    enum Mode {
        case paused
        case observing
    }

    private let environment: AppEnvironment
    private var mode: Mode = .paused
    private let cameraAttentionService = CameraAttentionService()
    private var sensor: WorkspaceSensor?
    private var currentFocus: AppFocusSnapshot?
    private var currentFocusStartedAt: Date?
    private var latestAttention: AttentionSnapshot?
    private var latestAttentionAt: Date?
    private var lastFacePresentAttention: AttentionSnapshot?
    private var consecutiveMissingFaceSamples = 0
    private var latestCameraStatus: String?
    private var cameraAccessRequestInFlight = false
    private var lastCameraPermissionStatus: String?
    private var latestInputActivity: InputActivitySnapshot?
    private var latestHint: String?
    private var latestContextLine: String?
    private var latestContextLineAt: Date?
    private var lastHintAt: Date?
    private var focusChangeTimestamps: [Date] = []
    private var lastActivityInsight: String?
    private var lastActivityInsightAt: Date?
    private var lastBehaviorCueName: String?
    private var lastBehaviorCueAt: Date?
    private var lastTextAffectCueKey: String?
    private var lastTextAffectCueAt: Date?
    private var lastGazeCalibrationKey: String?
    private var lastGazeCalibrationAt: Date?
    private var lastAwayPresenceIncidentAt: Date?
    private var lastSmileCueAt: Date?
    private var lastWritingContextAt: Date?
    private var lastOCRWritingFallbackAt: Date?
    private var lastOCRWritingFallbackKey: String?
    private var isIdleBoundaryOpen = false
    private var sessionStartedAt: Date?
    private var summaryTimer: Timer?
    private var mediaTimer: Timer?
    private var lastMediaPlaybackKey: String?
    private var lastMediaPlaybackSnapshot: MediaPlaybackSnapshot?
    private var currentMediaTrackKey: String?
    private var currentMediaTrackStartedAt: Date?
    private var lastAutoPauseAt: Date?
    private var lastHeadphonesAutoPauseAt: Date?
    private var lastAudioOutputLooksLikeHeadphones: Bool?
    private var autoPausedSources: [String] = []

    var onStateChanged: ((ObserverViewState) -> Void)?

    init(environment: AppEnvironment) {
        self.environment = environment
        self.sensor = WorkspaceSensor(
            topology: environment.topology,
            screenContextRefreshInterval: environment.settings.screenContextRefreshSeconds,
            isContentAllowed: { appID in
                guard let appID else {
                    return false
                }
                return environment.privacyStore.isContentAllowed(appID)
            }
        )
    }

    var dataFolder: URL {
        environment.dataDirectory
    }

    var settings: ObserverSettings {
        environment.settings
    }

    var currentSetupDescription: String {
        environment.topology.debugDescription
    }

    var hasGeminiAPIKey: Bool {
        KeychainStore.geminiAPIKey.hasPassword()
    }

    var stateSnapshot: ObserverViewState {
        ObserverViewState(
            mode: mode,
            appName: currentFocus?.appName,
            contextText: currentWidgetContextText(),
            sessionStartedAt: sessionStartedAt,
            attentionText: latestCameraStatus ?? currentActivityInsightText(),
            hintText: currentWidgetHintText()
        )
    }

    private func currentWidgetContextText(now: Date = Date()) -> String {
        if let latestContextLine,
           let latestContextLineAt,
           now.timeIntervalSince(latestContextLineAt) <= 150 {
            return latestContextLine
        }

        return currentFocus?.shortContextText ?? "No active context yet"
    }

    private func currentWidgetHintText(now: Date = Date()) -> String? {
        guard let latestHint, let lastHintAt else {
            return nil
        }
        return now.timeIntervalSince(lastHintAt) <= 150 ? latestHint : nil
    }

    private func setLatestContextLine(_ line: String?, now: Date = Date()) {
        latestContextLine = line
        latestContextLineAt = line == nil ? nil : now
    }

    private var smoothedAttentionForDisplay: AttentionSnapshot? {
        guard let latestAttention else {
            return nil
        }

        if latestAttention.facePresent {
            return latestAttention
        }

        if consecutiveMissingFaceSamples < 4, let lastFacePresentAttention {
            return lastFacePresentAttention.asTemporarilyLostFace()
        }

        return latestAttention
    }

    private var recentFocusChangesCount: Int {
        let cutoff = Date().addingTimeInterval(-60)
        focusChangeTimestamps.removeAll { $0 < cutoff }
        return focusChangeTimestamps.count
    }

    private func currentActivityInsightText() -> String {
        ActivityInsightBuilder().build(
            attention: smoothedAttentionForDisplay,
            input: latestInputActivity,
            topology: environment.topology,
            currentFocus: currentFocus,
            currentFocusStartedAt: currentFocusStartedAt,
            focusChangesLastMinute: recentFocusChangesCount
        )
    }

    func recordLaunch() {
        append(
            .init(
                type: .appLaunch,
                payload: ["data_directory": environment.dataDirectory.path],
                workspaceTopologyVersion: environment.topology.version
            )
        )
        append(
            .init(
                type: .workspaceTopologyLoaded,
                payload: environment.topology.eventPayload,
                workspaceTopologyVersion: environment.topology.version
            )
        )
    }

    func recordShutdown() {
        append(.init(type: .appShutdown, workspaceTopologyVersion: environment.topology.version))
    }

    func startObserving() {
        guard mode != .observing else {
            return
        }
        mode = .observing
        sessionStartedAt = Date()
        append(.init(type: .observingStarted, workspaceTopologyVersion: environment.topology.version))
        append(
            .init(
                type: .sessionBoundary,
                payload: ["boundary": "session_started"],
                workspaceTopologyVersion: environment.topology.version
            )
        )
        sensor?.start { [weak self] event in
            self?.handleSensorEvent(event)
        }
        startSummaryTimer()
        startMediaTimer()
        notifyStateChanged()
    }

    func pauseObserving() {
        guard mode != .paused else {
            return
        }
        mode = .paused
        sessionStartedAt = nil
        append(.init(type: .observingPaused, workspaceTopologyVersion: environment.topology.version))
        closeCurrentFocusInterval(reason: "paused")
        append(
            .init(
                type: .sessionBoundary,
                payload: ["boundary": "session_paused"],
                workspaceTopologyVersion: environment.topology.version
            )
        )
        sensor?.stop()
        stopSummaryTimer()
        stopMediaTimer()
        notifyStateChanged()
    }

    func startCameraAttention() {
        let status = PermissionAdvisor.currentStatus().camera
        recordCameraPermissionStatus(status)

        if cameraAttentionService.isActive {
            latestCameraStatus = nil
            notifyStateChanged()
            return
        }

        if status == "authorized" {
            startCameraCapture()
            return
        }

        guard status == "not_determined" else {
            latestCameraStatus = "Жду активности · камера запрещена"
            notifyStateChanged()
            print("Camera access not granted.")
            return
        }

        guard !cameraAccessRequestInFlight else {
            latestCameraStatus = "Жду активности · жду разрешение камеры"
            notifyStateChanged()
            return
        }

        cameraAccessRequestInFlight = true
        latestCameraStatus = "Жду активности · запрашиваю камеру"
        notifyStateChanged()
        PermissionAdvisor.requestCameraAccess { [weak self] granted in
            guard let self else {
                return
            }
            self.cameraAccessRequestInFlight = false
            let currentStatus = PermissionAdvisor.currentStatus().camera
            self.recordCameraPermissionStatus(currentStatus, force: true)

            guard granted else {
                self.latestCameraStatus = "Жду активности · камера запрещена"
                self.notifyStateChanged()
                print("Camera access not granted.")
                return
            }

            self.startCameraCapture()
        }
    }

    func stopCameraAttention() {
        cameraAttentionService.stop()
        latestAttention = nil
        lastFacePresentAttention = nil
        consecutiveMissingFaceSamples = 0
        latestCameraStatus = nil
        append(
            .init(
                type: .cameraAttentionStopped,
                workspaceTopologyVersion: environment.topology.version
            )
        )
        notifyStateChanged()
    }

    func reconcileCameraPermissionAndStartIfNeeded() {
        let status = PermissionAdvisor.currentStatus().camera
        recordCameraPermissionStatus(status)

        switch status {
        case "authorized":
            if environment.settings.startCameraAttentionOnLaunch, !cameraAttentionService.isActive {
                startCameraCapture()
            }
        case "denied", "restricted":
            latestCameraStatus = "Жду активности · камера запрещена"
            notifyStateChanged()
        case "not_determined":
            if latestCameraStatus == "Жду активности · запрашиваю камеру" {
                return
            }
            latestCameraStatus = cameraAccessRequestInFlight
                ? "Жду активности · жду разрешение камеры"
                : "Жду активности · камера ждет разрешения"
            notifyStateChanged()
        default:
            latestCameraStatus = "Жду активности · камера недоступна"
            notifyStateChanged()
        }
    }

    func collectContextPack() -> String {
        let events = (try? environment.eventStore.recentEvents(limit: 80)) ?? []
        let pack = ContextPackBuilder(topology: environment.topology).build(events: events, mode: mode)
        append(
            .init(
                type: .contextPackGenerated,
                payload: ["event_count": "\(events.count)"],
                workspaceTopologyVersion: environment.topology.version
            )
        )
        return pack
    }

    func exportContextFile() -> URL? {
        do {
            return try ArtifactExporter(directory: environment.dataDirectory).export(
                name: "context-pack",
                contents: collectContextPack()
            )
        } catch {
            print("Failed to export context file: \(error)")
            return nil
        }
    }

    func exportEventsJSONL() -> URL? {
        do {
            let events = try environment.eventStore.allEvents()
            return try EventExporter().exportJSONL(events: events, directory: environment.dataDirectory)
        } catch {
            print("Failed to export events: \(error)")
            return nil
        }
    }

    func generateLocalSummary() -> String {
        let events = (try? environment.eventStore.recentEvents(limit: 250)) ?? []
        appendDetectorEvents(from: events)
        let summary = LocalSummaryBuilder().build(events: events)
        append(
            .init(
                type: .localSummary,
                payload: [
                    "summary": summary,
                    "event_count": "\(events.count)"
                ],
                workspaceTopologyVersion: environment.topology.version
            )
        )
        return summary
    }

    func generateResearchDigest() -> String {
        let events = (try? environment.eventStore.recentEvents(limit: 500)) ?? []
        let digest = ResearchDigestBuilder().build(events: events)
        append(
            .init(
                type: .researchDigest,
                payload: [
                    "digest": digest,
                    "event_count": "\(events.count)"
                ],
                workspaceTopologyVersion: environment.topology.version
            )
        )
        return digest
    }

    func exportResearchDigest() -> URL? {
        do {
            return try ArtifactExporter(directory: environment.dataDirectory).export(
                name: "research-digest",
                contents: generateResearchDigest()
            )
        } catch {
            print("Failed to export research digest: \(error)")
            return nil
        }
    }

    func generateLocalLLMInsight() {
        let events = (try? environment.eventStore.recentEvents(limit: 250)) ?? []
        let context = ContextPackBuilder(topology: environment.topology).build(events: events, mode: mode)

        Task {
            do {
                let insight = try await OllamaInsightProvider().generateInsight(context: context)
                await MainActor.run {
                    self.append(
                        .init(
                            type: .localInsight,
                            payload: [
                                "provider": "ollama",
                                "insight": insight
                            ],
                            workspaceTopologyVersion: self.environment.topology.version
                        )
                    )
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(insight, forType: .string)
                    print(insight)
                }
            } catch {
                print("Local LLM insight unavailable: \(error)")
            }
        }
    }

    func setGeminiAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("Gemini API key was empty; nothing saved.")
            return
        }

        do {
            try KeychainStore.geminiAPIKey.setPassword(trimmed)
            append(
                .init(
                    type: .geminiKeyUpdated,
                    payload: ["storage": "keychain"],
                    workspaceTopologyVersion: environment.topology.version
                )
            )
            print("Gemini API key saved in Keychain.")
        } catch {
            print("Failed to save Gemini API key: \(error)")
        }
    }

    func deleteGeminiAPIKey() {
        do {
            try KeychainStore.geminiAPIKey.deletePassword()
            append(
                .init(
                    type: .geminiKeyDeleted,
                    payload: ["storage": "keychain"],
                    workspaceTopologyVersion: environment.topology.version
                )
            )
            print("Gemini API key deleted from Keychain.")
        } catch {
            print("Failed to delete Gemini API key: \(error)")
        }
    }

    func generateGeminiInsight() {
        guard environment.settings.geminiEnabled else {
            print("Gemini is disabled in Observer settings.")
            return
        }

        let keyFromKeychain = try? KeychainStore.geminiAPIKey.password()
        let keyFromEnvironment = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
            ?? ProcessInfo.processInfo.environment["GOOGLE_API_KEY"]
        let apiKey = (keyFromKeychain ?? keyFromEnvironment)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let apiKey, !apiKey.isEmpty else {
            print("Gemini API key is not configured. Use Set Gemini API Key first.")
            return
        }

        let events = (try? environment.eventStore.recentEvents(limit: 500)) ?? []
        appendDetectorEvents(from: events)
        let context = ContextPackBuilder(topology: environment.topology).build(events: events, mode: mode)
        let digest = ResearchDigestBuilder().build(events: events)
        let attention = stateSnapshot.attentionText
        let prompt = GeminiInsightProvider.buildPrompt(context: context, digest: digest, attention: attention)
        let model = environment.settings.geminiModel
        let budgetDecision = GeminiBudgetGuard().evaluate(
            events: events,
            budgetEUR: environment.settings.geminiDailyBudgetEUR,
            estimatedCostPerRequestEUR: environment.settings.geminiEstimatedCostPerRequestEUR
        )

        guard budgetDecision.allowed else {
            append(
                .init(
                    type: .externalLLMRequest,
                    payload: [
                        "provider": "gemini",
                        "model": model,
                        "request_kind": "work_insight",
                        "status": "blocked_budget",
                        "spent_today_eur": String(format: "%.4f", budgetDecision.spentTodayEUR),
                        "projected_spend_eur": String(format: "%.4f", budgetDecision.projectedSpendEUR),
                        "daily_budget_eur": String(format: "%.2f", budgetDecision.budgetEUR)
                    ],
                    workspaceTopologyVersion: environment.topology.version
                )
            )
            print("Gemini daily budget reached. Request skipped.")
            return
        }

        append(
            .init(
                type: .externalLLMRequest,
                payload: [
                    "provider": "gemini",
                    "model": model,
                    "request_kind": "work_insight",
                    "status": "started",
                    "prompt_chars": "\(prompt.count)",
                    "estimated_cost_eur": String(format: "%.4f", environment.settings.geminiEstimatedCostPerRequestEUR),
                    "spent_today_eur": String(format: "%.4f", budgetDecision.spentTodayEUR),
                    "daily_budget_eur": String(format: "%.2f", budgetDecision.budgetEUR)
                ],
                workspaceTopologyVersion: environment.topology.version
            )
        )

        Task {
            do {
                let insight = try await GeminiInsightProvider(
                    apiKey: apiKey,
                    model: model
                ).generateInsight(context: context, digest: digest, attention: attention)

                await MainActor.run {
                    self.append(
                        .init(
                            type: .geminiInsight,
                            payload: [
                                "provider": "gemini",
                                "model": model,
                                "insight": insight
                            ],
                            workspaceTopologyVersion: self.environment.topology.version
                        )
                    )
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(insight, forType: .string)
                    print(insight)
                }
            } catch {
                await MainActor.run {
                    self.append(
                        .init(
                            type: .externalLLMRequest,
                            payload: [
                                "provider": "gemini",
                                "model": model,
                                "request_kind": "work_insight",
                                "status": "failed",
                                "error": String(describing: error)
                            ],
                            workspaceTopologyVersion: self.environment.topology.version
                        )
                    )
                    print("Gemini insight unavailable: \(error)")
                }
            }
        }
    }

    func copyDiagnostics() -> String {
        let counts = (try? environment.eventStore.eventCountsByType()) ?? [:]
        return DiagnosticsBuilder().build(
            dataDirectory: environment.dataDirectory,
            topology: environment.topology,
            settings: environment.settings,
            eventCounts: counts,
            currentFocus: currentFocus,
            latestAttention: latestAttention,
            permissions: PermissionAdvisor.currentStatus(),
            mode: mode,
            hasGeminiAPIKey: hasGeminiAPIKey
        )
    }

    func timelineText() -> String {
        let events = (try? environment.eventStore.recentEvents(limit: 160)) ?? []
        return TimelineFormatter().format(events: events)
    }

    func addUserNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        var payload: [String: String] = ["note": trimmed]
        if let currentFocus {
            payload["app_name"] = currentFocus.appName
            if let appID = currentFocus.appID {
                payload["app_id"] = appID
            }
        }

        append(
            .init(
                type: .userNote,
                appID: currentFocus?.appID,
                payload: payload,
                workspaceTopologyVersion: environment.topology.version
            )
        )
    }

    func deleteEventsFromLastHour() {
        do {
            try environment.eventStore.deleteEvents(since: Date().addingTimeInterval(-3600))
        } catch {
            print("Failed to delete last hour: \(error)")
        }
    }

    func resetLocalMemory() {
        do {
            try environment.eventStore.deleteAllEvents()
            latestHint = nil
            notifyStateChanged()
        } catch {
            print("Failed to reset local memory: \(error)")
        }
    }

    func excludeCurrentApp() {
        guard let currentFocus, let appID = currentFocus.appID else {
            return
        }

        do {
            try environment.privacyStore.addExcludedApp(appID)
            append(
                .init(
                    type: .privacyExclusionAdded,
                    appID: appID,
                    payload: ["app_name": currentFocus.appName],
                    workspaceTopologyVersion: environment.topology.version
                )
            )
        } catch {
            print("Failed to save privacy exclusion: \(error)")
        }
    }

    func allowCurrentAppContext() {
        guard let currentFocus, let appID = currentFocus.appID else {
            return
        }

        do {
            try environment.privacyStore.addAllowedApp(appID)
            append(
                .init(
                    type: .privacyAllowlistAdded,
                    appID: appID,
                    payload: ["app_name": currentFocus.appName],
                    workspaceTopologyVersion: environment.topology.version
                )
            )
            sensor?.refreshNow()
        } catch {
            print("Failed to save content allowlist: \(error)")
        }
    }

    func requestAccessibilityAccess() {
        let granted = PermissionAdvisor.requestAccessibilityAccess()
        print("Accessibility access granted: \(granted)")
    }

    func requestScreenRecordingAccess() {
        let granted = PermissionAdvisor.requestScreenRecordingAccess()
        print("Screen recording access granted: \(granted)")
    }

    func requestCameraAccess() {
        PermissionAdvisor.requestCameraAccess { granted in
            print("Camera access granted: \(granted)")
        }
    }

    func captureOCRForCurrentApp() {
        guard
            let currentFocus,
            let appID = currentFocus.appID,
            environment.privacyStore.isContentAllowed(appID)
        else {
            print("OCR skipped: current app is not content-allowlisted.")
            return
        }

        do {
            guard let result = try ScreenOCRService().recognizeText(for: currentFocus) else {
                print("OCR skipped: no capturable window found.")
                return
            }

            append(
                .init(
                    type: .ocrContext,
                    displayRole: currentFocus.displayRole,
                    appID: appID,
                    confidence: result.confidence,
                    payload: result.eventPayload,
                    workspaceTopologyVersion: environment.topology.version
                )
            )
        } catch {
            print("OCR failed: \(error)")
        }
    }

    private func append(_ event: ObserverEvent) {
        do {
            try environment.eventStore.append(event)
        } catch {
            print("Failed to write event: \(error)")
        }
    }

    private func startCameraCapture() {
        guard !cameraAttentionService.isActive else {
            latestCameraStatus = nil
            notifyStateChanged()
            return
        }

        do {
            latestCameraStatus = "Жду активности · камера включается"
            try cameraAttentionService.start(
                minimumEmitInterval: environment.settings.attentionSampleIntervalSeconds
            ) { [weak self] snapshot in
                self?.handleAttentionSnapshot(snapshot)
            }
            append(
                .init(
                    type: .cameraAttentionStarted,
                    payload: ["sample_interval_seconds": "\(Int(environment.settings.attentionSampleIntervalSeconds))"],
                    workspaceTopologyVersion: environment.topology.version
                )
            )
            notifyStateChanged()
        } catch {
            latestCameraStatus = "Жду активности · камера не запустилась"
            notifyStateChanged()
            print("Camera attention failed to start: \(error)")
        }
    }

    private func recordCameraPermissionStatus(_ status: String, force: Bool = false) {
        guard force || status != lastCameraPermissionStatus else {
            return
        }

        lastCameraPermissionStatus = status
        append(
            .init(
                type: .cameraPermission,
                payload: ["status": status],
                workspaceTopologyVersion: environment.topology.version
            )
        )
    }

    private func appendDetectorEvents(from events: [ObserverEvent]) {
        let recentDetectorNames = Set(
            events.suffix(80)
                .filter { $0.type == .detectorFired }
                .compactMap { $0.payload["detector"] }
        )

        for detection in DetectorEngine(settings: environment.settings.detectorSettings).evaluate(events: events) where !recentDetectorNames.contains(detection.name) {
            append(
                .init(
                    type: .detectorFired,
                    confidence: detection.confidence,
                    payload: detection.payload,
                    workspaceTopologyVersion: environment.topology.version
                )
            )
            if let hint = HintEngine().hint(for: detection) {
                let shouldSurfaceHint = environment.settings.hintDeliveryMode != "off"
                    && lastHintAt.map { Date().timeIntervalSince($0) >= environment.settings.minimumHintIntervalSeconds } != false

                if shouldSurfaceHint && environment.settings.hintDeliveryMode == "quiet" {
                    latestHint = hint
                    lastHintAt = Date()
                }
                append(
                    .init(
                        type: .hintCandidate,
                        confidence: detection.confidence,
                        payload: [
                            "source_detector": detection.name,
                            "hint": hint,
                            "delivery_mode": environment.settings.hintDeliveryMode,
                            "surfaced_in_widget": shouldSurfaceHint ? "true" : "false"
                        ],
                        workspaceTopologyVersion: environment.topology.version
                    )
                )
                if shouldSurfaceHint {
                    notifyStateChanged()
                }
            }
        }
    }

    private func handleAttentionSnapshot(_ snapshot: AttentionSnapshot) {
        let previousAttention = latestAttention
        let previousAttentionAt = latestAttentionAt
        let missingFaceSamplesBeforeCurrent = consecutiveMissingFaceSamples
        let now = Date()
        latestAttention = snapshot
        latestAttentionAt = now
        if snapshot.facePresent {
            lastFacePresentAttention = snapshot
            consecutiveMissingFaceSamples = 0
        } else {
            consecutiveMissingFaceSamples += 1
        }
        latestCameraStatus = nil
        append(
            .init(
                type: .attention,
                confidence: snapshot.confidence,
                payload: snapshot.eventPayload,
                workspaceTopologyVersion: environment.topology.version
            )
        )
        recordBehaviorCueIfNeeded(
            previousAttention: previousAttention,
            currentAttention: snapshot,
            secondsSincePreviousAttention: previousAttentionAt.map { now.timeIntervalSince($0) },
            now: now
        )
        recordSmileCueIfNeeded(snapshot, now: now)
        recordAwayPresenceIncidentIfNeeded(
            currentAttention: snapshot,
            missingFaceSamplesBeforeCurrent: missingFaceSamplesBeforeCurrent,
            now: now
        )
        recordGazeCalibrationSampleIfNeeded(now: now)
        pauseMediaIfUserAppearsAway()
        resumeMediaIfUserReturned()
        notifyStateChanged()
    }

    private func handleSensorEvent(_ sensorEvent: SensorEvent) {
        switch sensorEvent {
        case .displayInventory(let displays):
            append(
                .init(
                    type: .displayInventory,
                    payload: displays.eventPayload,
                    workspaceTopologyVersion: environment.topology.version
                )
            )

        case .appFocus(let focus):
            focusChangeTimestamps.append(Date())
            focusChangeTimestamps = focusChangeTimestamps.suffix(20)
            closeCurrentFocusInterval(reason: "focus_changed")
            currentFocus = focus
            currentFocusStartedAt = Date()
            setLatestContextLine(nil)
            append(
                .init(
                    type: .appFocus,
                    displayRole: focus.displayRole,
                    appID: focus.appID,
                    confidence: focus.windowTitle == nil ? 0.75 : 0.95,
                    payload: focus.eventPayload,
                    workspaceTopologyVersion: environment.topology.version
                )
            )
            notifyStateChanged()

        case .inputActivity(let activity):
            latestInputActivity = activity
            append(
                .init(
                    type: .inputActivity,
                    confidence: 0.8,
                    payload: activity.eventPayload,
                    workspaceTopologyVersion: environment.topology.version
                )
            )
            updateIdleBoundary(activity)
            recordGazeCalibrationSampleIfNeeded()
            captureOCRWritingFallbackIfNeeded(activity)
            pauseMediaIfUserAppearsAway()
            resumeMediaIfUserReturned()
            notifyStateChanged()

        case .screenContext(let context):
            setLatestContextLine(context.shortDisplayLine(prefix: "Контекст"))
            append(
                .init(
                    type: .screenContext,
                    displayRole: context.displayRole,
                    appID: context.appID,
                    confidence: context.confidence,
                    payload: context.eventPayload,
                    workspaceTopologyVersion: environment.topology.version
                )
            )

        case .writingContext(let context):
            var payload = context.eventPayload
            payload["context_kind"] = "active_writing"
            lastWritingContextAt = Date()
            setLatestContextLine(context.shortDisplayLine(prefix: "Пишет"))
            recordTextAffectCueIfNeeded(
                text: context.focusedElementValue ?? context.selectedText,
                appName: context.appName
            )
            append(
                .init(
                    type: .writingContext,
                    displayRole: context.displayRole,
                    appID: context.appID,
                    confidence: context.confidence,
                    payload: payload,
                    workspaceTopologyVersion: environment.topology.version
                )
            )
        }
    }

    private func captureOCRWritingFallbackIfNeeded(_ activity: InputActivitySnapshot) {
        guard activity.secondsSinceKeyboard <= 8 else {
            return
        }
        guard let currentFocus, let appID = currentFocus.appID else {
            return
        }
        guard environment.privacyStore.isContentAllowed(appID) else {
            return
        }

        let now = Date()
        if let lastWritingContextAt, now.timeIntervalSince(lastWritingContextAt) < 20 {
            return
        }
        guard lastOCRWritingFallbackAt.map({ now.timeIntervalSince($0) >= 30 }) ?? true else {
            return
        }

        do {
            guard let result = try ScreenOCRService().recognizeText(for: currentFocus) else {
                lastOCRWritingFallbackAt = now
                return
            }

            let key = [result.appID ?? "", result.text].joined(separator: "|")
            guard key != lastOCRWritingFallbackKey else {
                lastOCRWritingFallbackAt = now
                return
            }

            lastOCRWritingFallbackAt = now
            lastOCRWritingFallbackKey = key
            var payload = result.eventPayload
            payload["context_kind"] = "writing_fallback"
            payload["fallback_reason"] = "accessibility_text_unavailable"
            recordTextAffectCueIfNeeded(text: result.text, appName: result.appName)
            append(
                .init(
                    type: .ocrContext,
                    displayRole: currentFocus.displayRole,
                    appID: result.appID,
                    confidence: min(result.confidence, 0.55),
                    payload: payload,
                    workspaceTopologyVersion: environment.topology.version
                )
            )
        } catch {
            lastOCRWritingFallbackAt = now
        }
    }

    private func recordTextAffectCueIfNeeded(text: String?, appName: String?) {
        guard let text else {
            return
        }
        guard let cue = TextAffectCueBuilder().build(
            text: text,
            appName: appName,
            activityInsight: lastActivityInsight
        ) else {
            return
        }

        let now = Date()
        let key = [cue.name, cue.payload["markers"] ?? ""].joined(separator: "|")
        let enoughTimePassed = lastTextAffectCueAt.map { now.timeIntervalSince($0) >= 60 } ?? true
        guard key != lastTextAffectCueKey || enoughTimePassed else {
            return
        }

        lastTextAffectCueKey = key
        lastTextAffectCueAt = now
        setLatestContextLine(cue.insight, now: now)
        append(
            .init(
                type: .behaviorCue,
                confidence: cue.confidence,
                payload: cue.payload,
                workspaceTopologyVersion: environment.topology.version
            )
        )
    }

    private func notifyStateChanged() {
        recordActivityInsightIfNeeded()
        onStateChanged?(stateSnapshot)
    }

    private func recordActivityInsightIfNeeded() {
        guard mode == .observing, latestCameraStatus == nil else {
            return
        }

        let insight = currentActivityInsightText()
        let now = Date()
        let enoughTimePassed = lastActivityInsightAt.map { now.timeIntervalSince($0) >= 60 } ?? true
        guard insight != lastActivityInsight || enoughTimePassed else {
            return
        }

        lastActivityInsight = insight
        lastActivityInsightAt = now

        var payload: [String: String] = ["insight": insight]
        if let currentFocus {
            payload["app_name"] = currentFocus.appName
            if let appID = currentFocus.appID {
                payload["app_id"] = appID
            }
            if let displayRole = currentFocus.displayRole {
                payload["focus_display_role"] = displayRole.rawValue
            }
        }
        if let input = latestInputActivity {
            payload["seconds_since_any_input"] = String(format: "%.1f", input.secondsSinceAnyInput)
            if let mouseDisplayRole = input.mouseDisplayRole {
                payload["mouse_display_role"] = mouseDisplayRole.rawValue
            }
        }
        if let attention = smoothedAttentionForDisplay {
            payload["face_present"] = attention.facePresent ? "true" : "false"
            if attention.isTemporarilyLostFace {
                payload["temporarily_lost_face"] = "true"
            }
        }

        append(
            .init(
                type: .activityInsight,
                displayRole: currentFocus?.displayRole,
                appID: currentFocus?.appID,
                confidence: 0.65,
                payload: payload,
                workspaceTopologyVersion: environment.topology.version
            )
        )
    }

    private func recordBehaviorCueIfNeeded(
        previousAttention: AttentionSnapshot?,
        currentAttention: AttentionSnapshot?,
        secondsSincePreviousAttention: TimeInterval?,
        now: Date = Date()
    ) {
        guard mode == .observing else {
            return
        }

        guard let cue = BehaviorCueBuilder().build(
            previousAttention: previousAttention,
            currentAttention: currentAttention,
            secondsSincePreviousAttention: secondsSincePreviousAttention,
            input: latestInputActivity,
            currentFocus: currentFocus,
            currentFocusStartedAt: currentFocusStartedAt,
            focusChangesLastMinute: recentFocusChangesCount,
            activityInsight: lastActivityInsight,
            now: now
        ) else {
            return
        }

        let enoughTimePassed = lastBehaviorCueAt.map { now.timeIntervalSince($0) >= 90 } ?? true
        guard cue.name != lastBehaviorCueName || enoughTimePassed else {
            return
        }

        lastBehaviorCueName = cue.name
        lastBehaviorCueAt = now
        append(
            .init(
                type: .behaviorCue,
                confidence: cue.confidence,
                payload: cue.payload,
                workspaceTopologyVersion: environment.topology.version
            )
        )

        let displayEligible = cue.payload["display_eligible"] != "false"
        if displayEligible, cue.name != "steady_focus" {
            latestHint = cue.insight
            lastHintAt = now
        }
    }

    private func recordGazeCalibrationSampleIfNeeded(now: Date = Date()) {
        guard mode == .observing else {
            return
        }

        guard let sample = GazeCalibrationBuilder().build(
            attention: smoothedAttentionForDisplay,
            input: latestInputActivity,
            currentFocus: currentFocus,
            activityInsight: lastActivityInsight
        ) else {
            return
        }

        let key = [
            sample.targetSource,
            sample.targetDisplayRole?.rawValue ?? "no-role",
            sample.targetScreenIndex.map(String.init) ?? "no-screen"
        ].joined(separator: "|")
        let enoughTimePassed = lastGazeCalibrationAt.map { now.timeIntervalSince($0) >= 8 } ?? true
        guard key != lastGazeCalibrationKey || enoughTimePassed else {
            return
        }

        lastGazeCalibrationKey = key
        lastGazeCalibrationAt = now
        append(
            .init(
                type: .gazeCalibrationSample,
                displayRole: sample.targetDisplayRole,
                appID: currentFocus?.appID,
                confidence: sample.confidence,
                payload: sample.payload,
                workspaceTopologyVersion: environment.topology.version
            )
        )
    }

    private func recordAwayPresenceIncidentIfNeeded(
        currentAttention: AttentionSnapshot,
        missingFaceSamplesBeforeCurrent: Int,
        now: Date = Date()
    ) {
        guard mode == .observing else {
            return
        }
        guard let incident = AwayPresenceIncidentBuilder().build(
            currentAttention: currentAttention,
            missingFaceSamplesBeforeCurrent: missingFaceSamplesBeforeCurrent,
            input: latestInputActivity,
            currentFocus: currentFocus,
            activityInsight: lastActivityInsight
        ) else {
            return
        }

        let enoughTimePassed = lastAwayPresenceIncidentAt.map { now.timeIntervalSince($0) >= 600 } ?? true
        guard enoughTimePassed else {
            return
        }

        lastAwayPresenceIncidentAt = now
        append(
            .init(
                type: .awayPresenceIncident,
                displayRole: currentFocus?.displayRole,
                appID: currentFocus?.appID,
                confidence: incident.confidence,
                payload: incident.payload,
                workspaceTopologyVersion: environment.topology.version
            )
        )
    }

    private func recordSmileCueIfNeeded(_ attention: AttentionSnapshot, now: Date = Date()) {
        guard mode == .observing else {
            return
        }
        guard attention.smileCandidate == true else {
            return
        }
        guard currentFocus?.isCommunicationContext == true || lastActivityInsight?.contains("Коммуникация") == true else {
            return
        }

        let enoughTimePassed = lastSmileCueAt.map { now.timeIntervalSince($0) >= 90 } ?? true
        guard enoughTimePassed else {
            return
        }

        lastSmileCueAt = now
        latestHint = "Коммуникация: улыбнулся на сообщение"
        lastHintAt = now

        var payload: [String: String] = [
            "cue": "positive_reaction_candidate",
            "interpretation": "smile_in_communication_context"
        ]
        if let score = attention.smileScore {
            payload["smile_score"] = String(format: "%.3f", score)
        }
        if let source = attention.smileSignalSource {
            payload["smile_signal_source"] = source
        }
        if let currentFocus {
            payload["app_name"] = currentFocus.appName
            if let appID = currentFocus.appID {
                payload["app_id"] = appID
            }
        }
        if let lastActivityInsight {
            payload["activity_insight"] = lastActivityInsight
        }

        append(
            .init(
                type: .behaviorCue,
                displayRole: currentFocus?.displayRole,
                appID: currentFocus?.appID,
                confidence: 0.58,
                payload: payload,
                workspaceTopologyVersion: environment.topology.version
            )
        )
        notifyStateChanged()
    }

    private func closeCurrentFocusInterval(reason: String) {
        guard let currentFocus, let currentFocusStartedAt else {
            return
        }

        let duration = Date().timeIntervalSince(currentFocusStartedAt)
        guard duration >= 1 else {
            return
        }

        var payload: [String: String] = [
            "app_name": currentFocus.appName,
            "duration_seconds": String(format: "%.1f", duration),
            "reason": reason
        ]
        if let appID = currentFocus.appID {
            payload["app_id"] = appID
        }
        if let displayRole = currentFocus.displayRole {
            payload["display_role"] = displayRole.rawValue
        }

        append(
            .init(
                type: .appFocusInterval,
                displayRole: currentFocus.displayRole,
                appID: currentFocus.appID,
                confidence: 0.9,
                payload: payload,
                workspaceTopologyVersion: environment.topology.version
            )
        )
        self.currentFocusStartedAt = nil
    }

    private func updateIdleBoundary(_ activity: InputActivitySnapshot) {
        let threshold = environment.settings.idleSessionBoundarySeconds
        if activity.secondsSinceAnyInput >= threshold, !isIdleBoundaryOpen {
            isIdleBoundaryOpen = true
            append(
                .init(
                    type: .sessionBoundary,
                    confidence: 0.8,
                    payload: [
                        "boundary": "idle_started",
                        "seconds_since_any_input": String(format: "%.1f", activity.secondsSinceAnyInput)
                    ],
                    workspaceTopologyVersion: environment.topology.version
                )
            )
        } else if activity.secondsSinceAnyInput < 10, isIdleBoundaryOpen {
            isIdleBoundaryOpen = false
            append(
                .init(
                    type: .sessionBoundary,
                    confidence: 0.8,
                    payload: ["boundary": "activity_resumed"],
                    workspaceTopologyVersion: environment.topology.version
                )
            )
        }
    }

    private func startSummaryTimer() {
        stopSummaryTimer()
        let interval = ProcessInfo.processInfo.environment["OBSERVER_SUMMARY_INTERVAL_SECONDS"]
            .flatMap(TimeInterval.init) ?? environment.settings.summaryIntervalSeconds

        summaryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                _ = self?.generateLocalSummary()
            }
        }
    }

    private func stopSummaryTimer() {
        summaryTimer?.invalidate()
        summaryTimer = nil
    }

    private func startMediaTimer() {
        stopMediaTimer()
        sampleMediaPlayback()
        mediaTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sampleMediaPlayback()
            }
        }
    }

    private func stopMediaTimer() {
        mediaTimer?.invalidate()
        mediaTimer = nil
        lastMediaPlaybackKey = nil
        currentMediaTrackKey = nil
        currentMediaTrackStartedAt = nil
        lastAudioOutputLooksLikeHeadphones = nil
    }

    private func sampleMediaPlayback() {
        handleAudioOutputTransition()

        guard let snapshot = MediaPlaybackService().currentPlayback() else {
            return
        }

        guard snapshot.identityKey != lastMediaPlaybackKey else {
            return
        }

        var payload = snapshot.eventPayload
        let userAppearsAway = userAppearsAwayForMediaPreference()
        if userAppearsAway {
            payload["preference_eligible"] = "false"
            payload["preference_reason"] = "away_or_idle"
        } else {
            payload["preference_eligible"] = "true"
        }
        if let currentFocus {
            payload["app_name"] = currentFocus.appName
            if let appID = currentFocus.appID {
                payload["app_id"] = appID
            }
        }
        if let latestInputActivity {
            payload["seconds_since_any_input"] = String(format: "%.1f", latestInputActivity.secondsSinceAnyInput)
            if let mouseDisplayRole = latestInputActivity.mouseDisplayRole {
                payload["mouse_display_role"] = mouseDisplayRole.rawValue
            }
        }
        if let lastActivityInsight {
            payload["activity_insight"] = lastActivityInsight
        }

        let now = Date()
        let previousSnapshot = lastMediaPlaybackSnapshot
        let secondsOnPrevious = currentMediaTrackStartedAt.map { now.timeIntervalSince($0) }
        append(
            .init(
                type: .mediaPlayback,
                payload: payload,
                workspaceTopologyVersion: environment.topology.version
            )
        )

        if let reaction = MediaReactionBuilder().build(
            previous: previousSnapshot,
            current: snapshot,
            secondsOnPrevious: secondsOnPrevious,
            userAppearsAway: userAppearsAway,
            activityInsight: lastActivityInsight,
            activeAppName: currentFocus?.appName
        ) {
            latestHint = reaction.insight
            lastHintAt = now
            append(
                .init(
                    type: .mediaReaction,
                    confidence: reaction.confidence,
                    payload: reaction.payload,
                    workspaceTopologyVersion: environment.topology.version
                )
            )
            notifyStateChanged()
        }

        if currentMediaTrackKey != snapshot.trackIdentityKey {
            currentMediaTrackKey = snapshot.trackIdentityKey
            currentMediaTrackStartedAt = now
        }
        lastMediaPlaybackKey = snapshot.identityKey
        lastMediaPlaybackSnapshot = snapshot
    }

    private func userAppearsAwayForMediaPreference() -> Bool {
        consecutiveMissingFaceSamples >= 4
            && (latestInputActivity?.secondsSinceAnyInput ?? 0) >= 45
    }

    private func handleAudioOutputTransition() {
        guard environment.settings.autoPauseMediaWhenAway else {
            return
        }
        guard mode == .observing else {
            return
        }

        let audioService = AudioOutputService()
        let outputName = audioService.currentOutputName()
        let outputLooksLikeHeadphones = audioService.looksLikeHeadphones(outputName)
        defer {
            lastAudioOutputLooksLikeHeadphones = outputLooksLikeHeadphones
        }

        if lastAudioOutputLooksLikeHeadphones == false, outputLooksLikeHeadphones == true {
            resumeMediaIfHeadphonesReturned(outputName: outputName)
            return
        }

        guard lastAudioOutputLooksLikeHeadphones == true, outputLooksLikeHeadphones == false else {
            return
        }

        let now = Date()
        guard lastHeadphonesAutoPauseAt.map({ now.timeIntervalSince($0) >= 30 }) ?? true else {
            return
        }

        var pausedSources = MediaPlaybackService().pauseAllKnownSources()
        let inferredPausedBySystem = pausedSources.isEmpty
            ? lastMediaPlaybackSnapshot?.sourceForObserverResume
            : nil
        if let inferredPausedBySystem {
            pausedSources = [inferredPausedBySystem]
        }

        lastHeadphonesAutoPauseAt = now
        if !pausedSources.isEmpty {
            lastAutoPauseAt = now
            autoPausedSources = pausedSources
            latestHint = inferredPausedBySystem == nil
                ? "Медиа: снял наушники, поставил на паузу"
                : "Медиа: снял наушники, запомнил паузу"
        } else {
            latestHint = "Медиа: снял наушники, уже тихо"
        }
        lastHintAt = now

        append(
            .init(
                type: .mediaPlayback,
                payload: [
                    "action": pausedSources.isEmpty
                        ? "auto_pause_skipped"
                        : (inferredPausedBySystem == nil ? "auto_pause" : "auto_pause_inferred"),
                    "reason": "headphones_removed",
                    "paused_sources": pausedSources.joined(separator: ", "),
                    "audio_output": outputName ?? "unknown"
                ],
                workspaceTopologyVersion: environment.topology.version
            )
        )
        notifyStateChanged()
    }

    private func resumeMediaIfHeadphonesReturned(outputName: String?) {
        guard environment.settings.autoResumeMediaWhenBack else {
            return
        }
        guard !autoPausedSources.isEmpty else {
            return
        }
        guard latestAttention?.facePresent == true else {
            return
        }
        guard let lastAutoPauseAt, Date().timeIntervalSince(lastAutoPauseAt) <= 1800 else {
            autoPausedSources = []
            return
        }

        let resumedSources = MediaPlaybackService().resumeSources(autoPausedSources)
        guard !resumedSources.isEmpty else {
            return
        }

        autoPausedSources = []
        latestHint = "Медиа: наушники вернулись, продолжил"
        lastHintAt = Date()
        append(
            .init(
                type: .mediaPlayback,
                payload: [
                    "action": "auto_resume",
                    "reason": "headphones_returned",
                    "resumed_sources": resumedSources.joined(separator: ", "),
                    "audio_output": outputName ?? "unknown"
                ],
                workspaceTopologyVersion: environment.topology.version
            )
        )
        notifyStateChanged()
    }

    private func pauseMediaIfUserAppearsAway() {
        guard environment.settings.autoPauseMediaWhenAway else {
            return
        }
        guard mode == .observing else {
            return
        }

        let inputIdleSeconds = latestInputActivity?.secondsSinceAnyInput ?? 0
        let listenerMissing = consecutiveMissingFaceSamples >= 2 && inputIdleSeconds >= 12
        let fullyAway = consecutiveMissingFaceSamples >= 4 && inputIdleSeconds >= 45
        guard listenerMissing || fullyAway else {
            return
        }

        let playbackSnapshot = lastMediaPlaybackSnapshot?.state == "playing"
            ? lastMediaPlaybackSnapshot
            : MediaPlaybackService().currentPlayback()
        guard playbackSnapshot?.state == "playing" else {
            return
        }

        let now = Date()
        guard lastAutoPauseAt.map({ now.timeIntervalSince($0) >= 60 }) ?? true else {
            return
        }

        let pausedSources = MediaPlaybackService().pauseAllKnownSources()
        guard !pausedSources.isEmpty else {
            return
        }

        lastAutoPauseAt = now
        autoPausedSources = pausedSources
        append(
            .init(
                type: .mediaPlayback,
                payload: [
                    "action": "auto_pause",
                    "reason": fullyAway ? "away_from_computer" : "listener_not_visible",
                    "paused_sources": pausedSources.joined(separator: ", "),
                    "missing_face_samples": "\(consecutiveMissingFaceSamples)",
                    "seconds_since_any_input": String(format: "%.1f", inputIdleSeconds),
                    "source": playbackSnapshot?.source ?? "unknown",
                    "title": playbackSnapshot?.title ?? ""
                ],
                workspaceTopologyVersion: environment.topology.version
            )
        )
    }

    private func resumeMediaIfUserReturned() {
        guard environment.settings.autoResumeMediaWhenBack else {
            return
        }
        guard !autoPausedSources.isEmpty else {
            return
        }
        guard let lastAutoPauseAt, Date().timeIntervalSince(lastAutoPauseAt) <= 1800 else {
            autoPausedSources = []
            return
        }
        guard latestAttention?.facePresent == true else {
            return
        }

        let outputName = AudioOutputService().currentOutputName()
        guard AudioOutputService().looksLikeHeadphones(outputName) else {
            return
        }

        let resumedSources = MediaPlaybackService().resumeSources(autoPausedSources)
        guard !resumedSources.isEmpty else {
            return
        }

        autoPausedSources = []
        append(
            .init(
                type: .mediaPlayback,
                payload: [
                    "action": "auto_resume",
                    "reason": "user_returned",
                    "resumed_sources": resumedSources.joined(separator: ", "),
                    "audio_output": outputName ?? "unknown"
                ],
                workspaceTopologyVersion: environment.topology.version
            )
        )
    }
}

private extension ScreenContextSnapshot {
    func shortDisplayLine(prefix: String) -> String? {
        let text = focusedElementValue ?? selectedText ?? windowTitle
        return text?.shortContextLine(prefix: prefix)
    }
}

private extension OCRResult {
    func shortDisplayLine(prefix: String) -> String? {
        text.shortContextLine(prefix: prefix)
    }
}

private extension String {
    func shortContextLine(prefix: String) -> String? {
        let cleaned = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return nil
        }

        let maxLength = 72
        if cleaned.count <= maxLength {
            return "\(prefix): \(cleaned)"
        }

        let index = cleaned.index(cleaned.startIndex, offsetBy: maxLength)
        return "\(prefix): \(cleaned[..<index])..."
    }
}

struct ObserverViewState {
    let mode: ObserverController.Mode
    let appName: String?
    let contextText: String
    let sessionStartedAt: Date?
    let attentionText: String
    let hintText: String?
}

extension ObserverController.Mode {
    var displayText: String {
        switch self {
        case .paused:
            return "Paused"
        case .observing:
            return "Watching"
        }
    }
}

private extension AppFocusSnapshot {
    var shortContextText: String {
        if let windowTitle, !windowTitle.isEmpty {
            return "\(appName) · \(windowTitle)"
        }
        return appName
    }

    var isCommunicationContext: Bool {
        [
            appName,
            appID ?? "",
            windowTitle ?? ""
        ]
        .joined(separator: " ")
        .lowercased()
        .containsAny([
            "whatsapp",
            "telegram",
            "signal",
            "messages",
            "slack",
            "mail",
            "gmail",
            "messenger",
            "viber"
        ])
    }
}

private extension String {
    func containsAny(_ needles: [String]) -> Bool {
        needles.contains { contains($0) }
    }
}
