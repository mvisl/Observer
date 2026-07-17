import AppKit
import Foundation

private struct PendingAwayPresenceIncident {
    let firstSeenAt: Date
    let payload: [String: String]
    let jpegData: Data?
    let displayRole: WorkspaceTopology.DisplayRole?
    let appID: String?
    let confidence: Double
}

private struct MediaListenSession {
    var trackKey: String
    var startedAt: Date
    var lastSeenAt: Date
    var observationSamples: Int
    var inputActiveSamples: Int
    var lastProfileEventAt: Date?
}

@MainActor
final class ObserverController {
    enum Mode {
        case offHours
        case paused
        case observing
    }

    private let environment: AppEnvironment
    private var mode: Mode = .paused
    private let cameraAttentionService = CameraAttentionService()
    private let ownerFaceRecognizer = OwnerFaceRecognizer()
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
    private var lastConfirmedPresenceAt: Date?
    private var awayStartedAt: Date?
    private var awayEpisodeClosed = false
    private var latestHint: String?
    private var latestContextLine: String?
    private var latestContextLineAt: Date?
    private var lastHintAt: Date?
    private var lastWidgetAppName: String?
    private var focusChangeTimestamps: [Date] = []
    private var lastAttentionSpanSignature: String?
    private var lastBehaviorCueName: String?
    private var lastBehaviorCueAt: Date?
    private var lastTextAffectCueKey: String?
    private var lastTextAffectCueAt: Date?
    private var lastGazeCalibrationKey: String?
    private var lastGazeCalibrationAt: Date?
    private var lastAwayPresenceIncidentAt: Date?
    private var pendingAwayPresenceIncident: PendingAwayPresenceIncident?
    private var lastSmileCueAt: Date?
    private var lastYawnCueAt: Date?
    private var cameraCueRateLimiter = CameraCueRateLimiter()
    private var mouthOpenCandidateStartedAt: Date?
    private var lastWritingContextAt: Date?
    private var lastOCRWritingFallbackAt: Date?
    private var lastOCRWritingFallbackKey: String?
    private var lastReadingOCRAt: Date?
    private var lastReadingOCRKey: String?
    private var isIdleBoundaryOpen = false
    private var isFineInputPauseOpen = false
    private var sessionStartedAt: Date?
    private var currentEpisodeStartedAt: Date?
    private var currentSessionID: String?
    private var currentEpisodeID: String?
    private var summaryTimer: Timer?
    private var heartbeatTimer: Timer?
    private var focusFlushTimer: Timer?
    private var geminiInsightTimer: Timer?
    private var mediaTimer: Timer?
    private var isMediaProbeInFlight = false
    private var isMediaActionInFlight = false
    private var predictionTimer: Timer?
    private var lastMediaPlaybackKey: String?
    private var lastMediaPlaybackSnapshot: MediaPlaybackSnapshot?
    private var currentMediaTrackKey: String?
    private var currentMediaTrackStartedAt: Date?
    private var currentMediaListenSession: MediaListenSession?
    private var lastMediaProbeFailureAt: Date?
    private var lastAutoPauseAt: Date?
    private var lastHeadphonesAutoPauseAt: Date?
    private var headphoneOutputTransitionGate = HeadphoneOutputTransitionGate()
    private var lastAudioActive: Bool?
    private var lastAudioActivityEventAt: Date?
    private var lastGeminiKeyAvailability: Bool?
    private var autoPausedSources: [String] = []
    private var headphoneWearStateMachine = HeadphoneWearStateMachine()
    private let headphoneAppearanceService = HeadphoneAppearanceService()
    private var recentMediaPageTracker = RecentMediaPageTracker()
    private var lastVisualObjectEventAt: [String: Date] = [:]
    private var lastCameraPersistedSignature: String?
    private var lastCameraPersistedAt: Date?
    private var lastCameraEvidenceSignature: String?
    private var lastCameraEvidenceAt: Date?
    private var localInsightCache: (interval: TimeInterval, createdAt: Date, text: String)?
    private var lastCognitiveEvaluationAt: Date?
    private var lastCameraHealthAt: Date?
    private var cameraHealthSamples: [(timestamp: Date, facePresent: Bool, confidence: Double)] = []
    private var scheduleOverride: ScheduleOverride?
    private var currentObservationIntervalStartedAt: Date?
    private var currentObservationOutsideDefaultSchedule = false
    private var latestCognitiveState: String?
    private var latestCognitiveStateStartedAt: Date?
    private var isAppendingContextFabric = false

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
                if environment.settings.fullContextMode {
                    return !environment.privacyStore.isExcluded(appID)
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
        GeminiKeyStore(directory: environment.dataDirectory).hasKey()
    }

    var stateSnapshot: ObserverViewState {
        ObserverViewState(
            mode: mode,
            appName: currentWidgetAppName(),
            contextText: currentWidgetContextText(),
            sessionStartedAt: sessionStartedAt,
            attentionText: latestCameraStatus ?? currentWidgetSensingText(),
            hintText: currentWidgetHintText(),
            securityIncidentCount: environment.securityIncidentStore.unseenCount(),
            calibration: currentWidgetCalibrationState()
        )
    }

    private func currentWidgetAppName() -> String? {
        guard let currentFocus else {
            return lastWidgetAppName
        }

        if currentFocus.isObserverApp {
            return lastWidgetAppName ?? currentFocus.appName
        }

        lastWidgetAppName = currentFocus.appName
        return currentFocus.appName
    }

    private func currentWidgetCalibrationState() -> WidgetCalibrationState {
        let topologyDisplays = widgetCalibrationDisplays()
        let prediction = widgetGazePrediction(displays: topologyDisplays)
        let displays = topologyDisplays.enumerated().map { index, display in
            let grid = display.isCameraMounted ? (columns: 3, rows: 3) : (columns: 2, rows: 2)
            return WidgetCalibrationDisplay(
                index: index,
                title: display.role.shortDisplayName,
                columns: grid.columns,
                rows: grid.rows,
                predictedCell: prediction.displayIndex == index ? prediction.cellIndex : nil
            )
        }
        let text: String
        if let displayIndex = prediction.displayIndex,
           let cellIndex = prediction.cellIndex,
           let display = displays.first(where: { $0.index == displayIndex }) {
            text = "Калибровка: думаю, \(display.title), зона \(cellIndex + 1)"
        } else {
            text = "Калибровка: камера ждёт устойчивый взгляд"
        }
        return WidgetCalibrationState(
            displays: displays,
            predictedDisplayIndex: prediction.displayIndex,
            predictedCellIndex: prediction.cellIndex,
            predictionText: text
        )
    }

    private func widgetCalibrationDisplays() -> [WorkspaceTopology.Display] {
        let screenCount = NSScreen.screens.count
        var displays = environment.topology.displays
        guard screenCount > displays.count else {
            return displays
        }

        if screenCount == 2 {
            displays = WorkspaceTopology.defaultTwoDisplaySetup.displays
        }
        while displays.count < screenCount {
            displays.append(.init(role: .unknown, position: .unknown, isCameraMounted: false))
        }
        return displays
    }

    private func widgetGazePrediction(displays: [WorkspaceTopology.Display]) -> (displayIndex: Int?, cellIndex: Int?) {
        guard !displays.isEmpty else {
            return (nil, nil)
        }
        guard let attention = smoothedAttentionForDisplay, attention.facePresent else {
            return fallbackCalibrationPrediction(displays: displays)
        }

        let displayIndex = predictedDisplayIndex(from: attention, displays: displays)
        let display = displays[displayIndex]
        let columns = display.isCameraMounted ? 3 : 2
        let rows = display.isCameraMounted ? 3 : 2
        let x = min(0.999, max(0, horizontalGazeProxy(attention)))
        let y = min(0.999, max(0, verticalGazeProxy(attention)))
        let column = min(columns - 1, max(0, Int((1 - x) * Double(columns))))
        let row = min(rows - 1, max(0, Int((1 - y) * Double(rows))))
        return (displayIndex, row * columns + column)
    }

    private func fallbackCalibrationPrediction(displays: [WorkspaceTopology.Display]) -> (displayIndex: Int?, cellIndex: Int?) {
        let displayIndex = displays.firstIndex(where: { $0.isCameraMounted }) ?? displays.indices.first
        guard let displayIndex else {
            return (nil, nil)
        }
        let display = displays[displayIndex]
        let columns = display.isCameraMounted ? 3 : 2
        let rows = display.isCameraMounted ? 3 : 2
        return (displayIndex, (rows / 2) * columns + (columns / 2))
    }

    private func horizontalGazeProxy(_ attention: AttentionSnapshot) -> Double {
        let faceX = attention.faceCenterX ?? 0.5
        guard let pupilX = averagePupilX(attention) else {
            return faceX
        }
        return faceX * 0.65 + pupilX * 0.35
    }

    private func verticalGazeProxy(_ attention: AttentionSnapshot) -> Double {
        let faceY = attention.faceCenterY ?? 0.5
        guard let pupilY = averagePupilY(attention) else {
            return faceY
        }
        return faceY * 0.65 + pupilY * 0.35
    }

    private func averagePupilX(_ attention: AttentionSnapshot) -> Double? {
        let values = [attention.leftPupilX, attention.rightPupilX].compactMap { $0 }
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    private func averagePupilY(_ attention: AttentionSnapshot) -> Double? {
        let values = [attention.leftPupilY, attention.rightPupilY].compactMap { $0 }
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    private func predictedDisplayIndex(from attention: AttentionSnapshot, displays: [WorkspaceTopology.Display]) -> Int {
        if displays.count == 1 {
            return 0
        }
        if let cameraIndex = displays.firstIndex(where: { $0.isCameraMounted }) {
            if abs(attention.yaw ?? 0) < 0.25, attention.facePosition == .center {
                return cameraIndex
            }
            let nonCameraIndexes = displays.indices.filter { $0 != cameraIndex }
            if let first = nonCameraIndexes.first {
                return first
            }
        }
        return 0
    }

    private var scheduleGate: ScheduleGate {
        ScheduleGate(
            settings: environment.settings.workSchedule,
            override: scheduleOverride
        )
    }

    private func currentWidgetContextText(now: Date = Date()) -> String {
        if let protectionLine = currentWidgetProtectionLine() {
            return protectionLine
        }

        if cameraEyesAreUnavailableForVisualClaims(now: now) {
            return "Глаза закрыты: не связываю это с экраном"
        }

        if let phoneLine = currentWidgetPhoneAttentionLine() {
            return phoneLine
        }

        if let attentionBoundaryLine = currentWidgetAttentionBoundaryLine() {
            return attentionBoundaryLine
        }

        if currentFocus?.isObserverApp == true {
            if let latestContextLine = usableCurrentContextLine(latestContextLine, now: now, maxAge: 45) {
                return latestContextLine
            }
        }

        if let latestContextLine,
           let latestContextLineAt,
           now.timeIntervalSince(latestContextLineAt) <= 75,
           let usableLine = usableCurrentContextLine(latestContextLine, now: now, maxAge: 75) {
            return usableLine
        }

        if let line = latestExternalWidgetInsightLine(now: now) {
            return line
        }

        if let hypothesis = currentWorkHypothesisLine(now: now),
           insightLineMatchesCurrentFocus(hypothesis) {
            return hypothesis
        }

        if let fallback = currentFocusFallbackLine(now: now) {
            return fallback
        }

        return "Рабочий эпизод: собираешь контекст в цельную гипотезу"
    }

    private func currentWidgetProtectionLine() -> String? {
        WidgetProtectionLineBuilder().build(
            appName: currentFocus?.appName,
            appID: currentFocus?.appID,
            facePresent: latestAttention?.facePresent,
            missingFaceSamples: consecutiveMissingFaceSamples,
            secondsSinceAnyInput: latestInputActivity?.secondsSinceAnyInput
        )
    }

    private func currentWidgetPhoneAttentionLine() -> String? {
        guard let attention = latestAttention,
              attention.facePresent,
              !attention.isTemporarilyLostFace
        else {
            return nil
        }
        guard (latestInputActivity?.secondsSinceAnyInput ?? 0) >= 8 else {
            return nil
        }

        let appName = currentFocus?.appName ?? "экран"
        let hasPhoneObject = attention.visualObjects.contains {
            let label = $0.label.lowercased()
            return label.contains("phone") || label.contains("mobile") || label.contains("smartphone")
        }
        if hasPhoneObject && attention.handNearFace {
            return "Фокус вне Mac: телефон в руках; не связываю паузу с \(appName)"
        }
        if attention.handNearFace && attention.looksLikePhoneAttention {
            return "Фокус вне Mac: смотришь в телефон; не связываю паузу с \(appName)"
        }
        if attention.handNearFace || attention.raisedHand {
            return "Пауза вне Mac: руки у лица; не приписываю её \(appName)"
        }
        return nil
    }

    private func currentWidgetAttentionBoundaryLine() -> String? {
        guard let attention = latestAttention,
              attention.facePresent,
              !attention.isTemporarilyLostFace
        else {
            return nil
        }
        guard (latestInputActivity?.secondsSinceAnyInput ?? 0) >= 20 else {
            return nil
        }

        let looksAway = attention.attentionZone == .offScreen
            || attention.pitch.map { $0 < -0.25 } == true
            || attention.yaw.map { abs($0) > 0.55 } == true
        guard looksAway else {
            return nil
        }

        let appName = currentFocus?.appName ?? "открытое приложение"
        return "Фокус: взгляд вне экрана; не связываю паузу с \(appName)"
    }

    private func currentFocusFallbackLine(now: Date = Date()) -> String? {
        let events = ((try? environment.eventStore.recentEvents(limit: 120)) ?? [])
            .filter { now.timeIntervalSince($0.timestamp) <= 10 * 60 }
        if let spanLine = latestAttentionSpanFallbackLine(events: events, now: now),
           insightLineMatchesCurrentFocus(spanLine) {
            return spanLine
        }

        let recentApps = orderedRecentAppNames(events: events)
        let joinedApps = recentApps.joined(separator: " ").lowercased()
        guard let currentFocus else {
            return "Observer: собираешь рабочий контекст в эпизод, а не в тики"
        }

        let appName = currentFocus.appName.lowercased()
        if appName.contains("chatgpt")
            || appName.contains("claude")
            || appName.contains("codex")
            || appName.contains("gemini") {
            if joinedApps.contains("figma") {
                return "Связка ИИ + дизайн: проверяешь, держится ли идея в макете"
            }
            if joinedApps.contains("chrome") || joinedApps.contains("safari") {
                return "Связка ИИ + веб: уточняешь тезис через несколько источников"
            }
            return "ИИ-итерация: уточняешь критерии результата, а не просто задачу"
        }
        if appName.contains("figma") {
            if joinedApps.contains("chatgpt") || joinedApps.contains("claude") {
                return "Дизайн + ИИ: сверяешь визуальное решение с формулировкой"
            }
            return "Дизайн: ищешь, где макет расходится с рабочей идеей"
        }
        if appName.contains("telegram")
            || appName.contains("whatsapp")
            || appName.contains("viber")
            || appName.contains("mail") {
            return "Переписка: связываешь разговор с текущим рабочим контекстом"
        }
        if currentFocus.isCommunicationContext {
            return personalCommunicationLine(events: events) ?? "Переписка: личный разговор, рабочие шаблоны не применяю"
        }
        if currentFocus.isJiraContext {
            return "Jira: выбираешь рабочий фронт, а не просто смотришь список"
        }
        if appName.contains("chrome") || appName.contains("safari") {
            if joinedApps.contains("chatgpt") || joinedApps.contains("claude") {
                return "Связка ИИ + веб: проверяешь гипотезу через внешний контекст"
            }
            if joinedApps.contains("figma") {
                return "Связка веб + дизайн: сверяешь экран с материалами задачи"
            }
            return "Исследование: отбираешь материал для текущего решения"
        }
        return "Рабочий фрагмент: собираешь несколько сигналов в один эпизод"
    }

    private func personalCommunicationLine(events: [ObserverEvent]) -> String? {
        let joined = events
            .filter { $0.type == .contentContext || $0.type == .userNote }
            .suffix(8)
            .compactMap { event in
                [
                    event.payload["source_entity_display_name"],
                    event.payload["entity_name"],
                    event.payload["topic"],
                    event.payload["raw_fragment"],
                    event.payload["summary"],
                    event.payload["note"]
                ]
                .compactMap { $0 }
                .joined(separator: " ")
            }
            .joined(separator: " ")
            .lowercased()
        if joined.contains("wife") || joined.contains("жена") || joined.contains("najoua") || joined.contains("beloved") {
            if joined.contains("song") || joined.contains("music") || joined.contains("chorus") || joined.contains("песня") {
                return "Переписка с женой: обсуждаете музыку и вкус, не рабочее исследование"
            }
            return "Переписка с женой: личный контекст, не рабочая задача"
        }
        return nil
    }

    private func latestAttentionSpanFallbackLine(events: [ObserverEvent], now: Date) -> String? {
        guard let span = events.last(where: { $0.type == .attentionSpan }),
              now.timeIntervalSince(span.timestamp) <= 90
        else {
            return nil
        }
        let apps = span.payload["apps"] ?? ""
        switch span.payload["span_kind"] {
        case "ai_assisted_design":
            return "Связка ИИ + дизайн: сверяешь идею через макет и ответы"
        case "ai_assisted_work":
            if apps.lowercased().contains("chrome") {
                return "Связка ИИ + веб: проверяешь тезис через несколько источников"
            }
            return "ИИ-итерация: уточняешь критерии результата через ответы"
        case "communication":
            return "Переписка: эпизод влияет на текущий рабочий контекст"
        case "design_work":
            return "Дизайн: проверяешь, собирается ли решение в цельный экран"
        case "mixed":
            return "Рабочая связка: несколько приложений держат один эпизод"
        default:
            return nil
        }
    }

    private func orderedRecentAppNames(events: [ObserverEvent]) -> [String] {
        var seen = Set<String>()
        return events
            .filter { $0.type == .appFocus || $0.type == .attentionSpan }
            .flatMap { event -> [String] in
                if event.type == .attentionSpan {
                    return (event.payload["apps"] ?? "").components(separatedBy: " -> ")
                }
                return [event.payload["app_name"] ?? event.appID ?? ""]
            }
            .filter { !$0.isEmpty }
            .filter { app in
                guard !seen.contains(app) else {
                    return false
                }
                seen.insert(app)
                return true
            }
    }

    private func latestExternalWidgetInsightLine(now: Date = Date()) -> String? {
        guard !cameraEyesAreUnavailableForVisualClaims(now: now) else {
            return nil
        }

        let maxAge: TimeInterval = 120
        return ((try? environment.eventStore.recentEvents(limit: 80)) ?? [])
            .reversed()
            .first { event in
                event.type == .geminiInsight
                    && now.timeIntervalSince(event.timestamp) <= maxAge
                    && event.payload["request_kind"] == "widget_sensemaking"
            }
            .flatMap { event in
                guard let cleaned = usableWidgetContextLine(event.payload["widget_line"]),
                      insightLineMatchesCurrentFocus(cleaned)
                else {
                    return nil
                }
                return cleaned
            }
    }

    private func currentWorkHypothesisLine(now: Date = Date()) -> String? {
        let events = ((try? environment.eventStore.recentEvents(limit: 120)) ?? [])
            .filter { now.timeIntervalSince($0.timestamp) <= 10 * 60 }
        guard !events.isEmpty else {
            return nil
        }

        let text = events
            .filter { $0.type == .contentContext || $0.type == .userNote }
            .suffix(8)
            .compactMap { event in
                [
                    usableSemanticTopic(event.payload["topic"]),
                    event.payload["raw_fragment"],
                    event.payload["summary"],
                    event.payload["note"]
                ]
                .compactMap { $0 }
                .joined(separator: " ")
            }
            .joined(separator: " ")
            .lowercased()

        let focusedApps = NSOrderedSet(array: events
            .filter { $0.type == .appFocus || $0.type == .attentionSpan }
            .compactMap { cleanInsightFragment($0.payload["app_name"]) })
            .array
            .compactMap { $0 as? String }
        let hasAI = focusedApps.contains { app in
            let lower = app.lowercased()
            return lower.contains("chatgpt") || lower.contains("claude") || lower.contains("gemini") || lower.contains("codex")
        }
        let hasDesign = focusedApps.contains { $0.lowercased().contains("figma") || $0.lowercased().contains("sketch") }
        let hasCommunication = focusedApps.contains { app in
            let lower = app.lowercased()
            return lower.contains("telegram") || lower.contains("whatsapp") || lower.contains("viber") || lower.contains("mail")
        } || events.contains { event in
            event.type == .contentContext && ["message", "email"].contains(event.payload["content_kind"])
        }
        let hasConfirmedSocialPositiveReaction = events.contains { event in
            guard event.type == .boundReaction,
                  event.confidence >= 0.75,
                  event.payload["competing_evidence"] == nil,
                  now.timeIntervalSince(event.timestamp) <= 180
            else {
                return false
            }
            let cue = (event.payload["cue"] ?? "").lowercased()
            let kind = event.payload["content_kind"] ?? ""
            let sentiment = event.payload["sentiment"] ?? ""
            return (cue.contains("positive") || cue.contains("smile"))
                && ["message", "email"].contains(kind)
                && sentiment != "neg"
        }
        let activeMedia = latestActiveMediaLine(events: events, now: now)
        let hasNegativeCharge = [
            "бесит", "злюсь", "хует", "хуй", "ебан", "еблан", "гандон", "тупым роботом", "shit", "fuck"
        ].contains { text.contains($0) }
        let hasProductPriorityTalk = [
            "приоритет", "главным", "второстепенным", "уровень", "тизер", "карточ", "продукт", "описан", "вопросик"
        ].contains { text.contains($0) }

        if hasCommunication && hasProductPriorityTalk && hasConfirmedSocialPositiveReaction {
            if let activeMedia {
                return "Переписка + музыка: спор разряжается, но источник подъёма разделяем (\(activeMedia))"
            }
            return "Переписка: спор о продукте разряжается шуткой"
        }
        if hasCommunication && hasProductPriorityTalk {
            return "Переписка: спор о приоритетах карточек и описаний"
        }
        if hasCommunication && hasNegativeCharge && hasConfirmedSocialPositiveReaction {
            if let activeMedia {
                return "Переписка + музыка: резкий тон похож на стёб; рядом играет \(activeMedia)"
            }
            return "Переписка: резкий тон похож на стёб, а не тупик"
        }
        if hasCommunication && hasNegativeCharge {
            return "Переписка: напряжение вокруг процесса и ответственности"
        }
        if hasCommunication && hasConfirmedSocialPositiveReaction {
            if let activeMedia {
                return "Переписка + музыка: подъём есть, источник надо разделить (\(activeMedia))"
            }
            return "Переписка: общение даёт лёгкий эмоциональный подъём"
        }

        if text.contains("телефон") && text.contains("карман") {
            return "Калибровка внимания: исправляешь ложный вывод про телефон"
        }
        if text.contains("санитар") || text.contains("второго") || text.contains("третьего") || text.contains("абстракц") {
            if hasAI && !hasCommunication {
                return "Observer: меняешь пилюлю с статуса на гипотезы"
            }
            return nil
        }
        if hasAI && text.contains("observer") && (text.contains("меря") || text.contains("измер") || text.contains("выборк") || text.contains("шум")) {
            return "Observer: проверяешь, меряет ли система смысл, а не шум"
        }
        if hasAI && text.contains("observer") && (text.contains("инсайт") || text.contains("паттерн") || text.contains("пилюл")) {
            return "Observer: настраиваешь переход от событий к паттернам"
        }
        if hasAI && (text.contains("observer") || text.contains("macos assistant") || text.contains("macos")) {
            return "Observer: уточняешь критерии полезного инсайта"
        }
        if text.contains("формулирует задачу") || text.contains("формирует задачу") {
            return "Смысл пилюли: убираешь пустые формулировки без конкретики"
        }
        if text.contains("рекомендац") && (text.contains("польза 0") || text.contains("ни о ч")) {
            return "Пилюля: чистишь рекомендации, которые не дают действия"
        }
        if text.contains("ocr") || text.contains("кашу") || text.contains("русск") {
            return "Контекст: чинишь чтение русского текста для точных инсайтов"
        }
        if hasAI && hasDesign && (text.contains("дизайн") || text.contains("макет") || text.contains("визуаль") || text.contains("карточ")) {
            return "Дизайн-ревью: сверяешь объяснение с реальным макетом"
        }

        return nil
    }

    private func latestActiveMediaLine(events: [ObserverEvent], now: Date = Date()) -> String? {
        guard let media = events.reversed().first(where: { event in
            event.type == .mediaPlayback
                && event.payload["state"] == "playing"
                && now.timeIntervalSince(event.timestamp) <= 10 * 60
        }) else {
            return nil
        }
        let source = cleanInsightFragment(media.payload["source"]) ?? "музыка"
        let title = cleanInsightFragment(media.payload["title"], allowShortCodeLikeText: false)
        let artist = cleanInsightFragment(media.payload["artist"], allowShortCodeLikeText: false)
        if let title, let artist {
            return "\(source): \(artist) - \(title)"
        }
        return title.map { "\(source): \($0)" } ?? source
    }

    private func usableWidgetContextLine(_ line: String?) -> String? {
        guard let cleaned = cleanInsightFragment(line, allowShortCodeLikeText: false),
              !isLowLevelWidgetContextLine(cleaned)
        else {
            return nil
        }
        return cleaned
    }

    private func usableCurrentContextLine(_ line: String?, now: Date = Date(), maxAge: TimeInterval) -> String? {
        guard !cameraEyesAreUnavailableForVisualClaims(now: now) else {
            return nil
        }

        guard let latestContextLineAt,
              now.timeIntervalSince(latestContextLineAt) <= maxAge,
              let cleaned = usableWidgetContextLine(line),
              insightLineMatchesCurrentFocus(cleaned)
        else {
            return nil
        }
        return cleaned
    }

    private func cameraEyesAreUnavailableForVisualClaims(now: Date = Date()) -> Bool {
        guard let latestAttention,
              latestAttention.facePresent,
              let latestAttentionAt,
              now.timeIntervalSince(latestAttentionAt) <= 45
        else {
            return false
        }

        return latestAttention.eyeVisibility == "occluded_or_unavailable"
    }

    private func insightLineMatchesCurrentFocus(_ line: String) -> Bool {
        guard let currentFocus else {
            return true
        }
        let lower = line.lowercased()
        if currentFocus.isCommunicationContext {
            return lower.hasPrefix("переписк")
                || lower.hasPrefix("сообщен")
                || lower.hasPrefix("почта")
                || lower.contains("жена")
                || lower.contains("личн")
        }
        if currentFocus.isJiraContext {
            return lower.hasPrefix("jira")
                || lower.contains("рабочий фронт")
                || lower.contains("приоритет")
                || lower.contains("разбор задач")
        }
        if currentFocus.isObserverApp {
            return lower.hasPrefix("observer")
                || lower.hasPrefix("пилюл")
                || lower.hasPrefix("контекст")
        }
        if lower.hasPrefix("переписк") || lower.hasPrefix("сообщен") {
            return currentFocus.isCommunicationContext
        }
        if lower.hasPrefix("observer") {
            return currentFocus.isObserverApp
        }
        if lower.hasPrefix("jira") {
            return currentFocus.isJiraContext
        }
        return true
    }

    private func usableSemanticTopic(_ topic: String?) -> String? {
        guard let cleaned = cleanInsightFragment(topic, allowShortCodeLikeText: false) else {
            return nil
        }
        let lower = cleaned.lowercased()
        if lower.hasPrefix("→")
            || lower.contains("google tran")
            || lower.contains("google trar")
            || lower.contains("inbox")
            || lower.contains("internal company bookmarks")
            || lower.contains("all bookmarks")
            || lower.contains("web.telegram.org")
            || lower.contains("chrome extension") {
            return nil
        }
        return cleaned
    }

    private func isLowLevelWidgetContextLine(_ line: String) -> Bool {
        let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return true
        }
        let exact = [
            "Диалог с ИИ",
            "Веб-контекст",
            "Коммуникация",
            "Рабочий контекст",
            "Активная работа",
            "Наблюдаю контекст"
        ]
        if exact.contains(normalized) {
            return true
        }
        let lower = normalized.lowercased()
        if lower.contains("собираю evidence")
            || lower.contains("evidence:")
            || lower.contains("нужен контекст + действие + реакция")
            || lower.contains("собираю контекст")
            || lower.contains("собираю сигналы")
            || lower.contains("нет уверенной гипотезы")
            || lower.contains("санитарку скрываю")
            || lower.contains("системный барьер")
            || lower.contains("эмоциональный подъём") {
            return true
        }
        if normalized.contains("долгая пауза") {
            return true
        }
        if normalized == "Защита: отошёл и прикрыл экран" {
            return true
        }
        if normalized.hasPrefix("Внешний анализ выключен:") {
            return true
        }
        return [
            "Диалог с ИИ: формулирует",
            "Диалог с ИИ: формирует",
            "Диалог с ИИ: читает",
            "Диалог с ИИ: отвлек",
            "Веб-контекст:",
            "Веб:",
            "Коммуникация: отвечает",
            "Коммуникация: читает",
            "Коммуникация: пишет",
            "Сообщения: читает",
            "Сообщения: пишет",
            "Почта: читает",
            "Почта: пишет",
            "Соцсети:",
            "Поиск / сравнение:",
            "Дизайн: правит",
            "Дизайн: рассматривает",
            "Дизайн: смотрит",
            "Дизайн: читает",
            "Дизайн: отвлек",
            "Код: активная",
            "Код: читает",
            "Код: работает",
            "Встреча:",
            "Рабочий контекст:",
            "Энергия просела:",
            "Сервисная настройка"
        ].contains { normalized.hasPrefix($0) }
    }

    private func currentWidgetHintText(now: Date = Date()) -> String? {
        guard let latestHint, let lastHintAt else {
            return nil
        }
        guard now.timeIntervalSince(lastHintAt) <= 45 else {
            return nil
        }
        return usableWidgetContextLine(latestHint)
    }

    private func currentWidgetSensingText() -> String { "" }

    private func lastMeaningfulEvidenceAt(now: Date = Date()) -> Date? {
        ((try? environment.eventStore.recentEvents(limit: 160)) ?? [])
            .reversed()
            .first { event in
                now.timeIntervalSince(event.timestamp) <= 30 * 60
                    && [.geminiInsight, .boundReaction, .episode, .attentionSpan, .fusionHypothesis, .contentContext].contains(event.type)
            }?
            .timestamp
    }

    private func relativeAgeLabel(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "сейчас"
        }
        if seconds < 3600 {
            return "\(Int(seconds / 60))м назад"
        }
        return "\(Int(seconds / 3600))ч назад"
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

    func recordLaunch() {
        append(
            .init(
                type: .appLaunch,
                payload: ["data_directory": environment.dataDirectory.path],
                workspaceTopologyVersion: environment.topology.version
            )
        )
        recordGeminiKeyStatusIfChanged()
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
        guard scheduleGate.status().sensorAllowed else {
            enterOffHours()
            return
        }
        mode = .observing
        let now = Date()
        let scheduleStatus = scheduleGate.status(at: now)
        sessionStartedAt = now
        currentEpisodeStartedAt = now
        currentSessionID = UUID().uuidString
        currentEpisodeID = UUID().uuidString
        currentObservationIntervalStartedAt = now
        currentObservationOutsideDefaultSchedule = scheduleStatus.outsideDefaultSchedule
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
        startStabilityTimers()
        startGeminiInsightTimer()
        startMediaTimer()
        startPredictionTimer()
        applyMorningTailIfNeeded(now: now)
        notifyStateChanged()
    }

    func pauseObserving() {
        guard mode != .paused else {
            return
        }
        mode = .paused
        closeCurrentEpisode(outcome: "manual_pause")
        sessionStartedAt = nil
        currentSessionID = nil
        currentEpisodeID = nil
        closeObservationInterval(reason: "manual_pause")
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
        stopStabilityTimers()
        stopGeminiInsightTimer()
        stopMediaTimer()
        stopPredictionTimer()
        notifyStateChanged()
    }

    func reconcileScheduleGate(now: Date = Date()) {
        let status = scheduleGate.status(at: now)
        if status.sensorAllowed {
            if mode == .offHours, environment.settings.startObservingOnLaunch {
                startObserving()
            }
            return
        }

        guard mode == .observing else {
            enterOffHours()
            return
        }

        closeForScheduleEnd(now: now)
    }

    func extendObservation(hours: Int) {
        let now = Date()
        let until = now.addingTimeInterval(Double(hours) * 3600)
        scheduleOverride = ScheduleOverride(until: until, reason: "manual_+\(hours)h")
        append(
            .init(
                type: .scheduleOverride,
                payload: [
                    "action": "extend",
                    "hours": "\(hours)",
                    "until": ISO8601DateFormatter().string(from: until),
                    "outside_default_schedule": scheduleGate.isInsideDefaultSchedule(now) ? "false" : "true"
                ],
                workspaceTopologyVersion: environment.topology.version
            )
        )
        if mode != .observing {
            startObserving()
        }
    }

    func startCameraAttention() {
        guard scheduleGate.status().sensorAllowed else {
            latestCameraStatus = nil
            enterOffHours()
            return
        }
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
        guard scheduleGate.status().sensorAllowed else {
            latestCameraStatus = nil
            if cameraAttentionService.isActive {
                stopCameraAttention()
            }
            notifyStateChanged()
            return
        }
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
        let pack = ContextPackBuilder(
            topology: environment.topology,
            pseudonymizeEntities: environment.settings.pseudonymizeEntities,
            entityAggregates: (try? environment.entityStore.aggregates()) ?? [:]
        ).build(events: events, mode: mode)
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
        updatePersonalBaselines(from: events)
        appendReadinessReports(from: events)
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

    func exportReadinessReport() -> URL? {
        do {
            let events = try environment.eventStore.allEvents()
            let report = buildReadinessMarkdown(events: events)
            return try ArtifactExporter(directory: environment.dataDirectory).export(
                name: "readiness-report",
                contents: report
            )
        } catch {
            print("Failed to export readiness report: \(error)")
            return nil
        }
    }

    func exportCausalUnderstandingReport() -> URL? {
        do {
            let events = try environment.eventStore.allEvents()
            appendCausalUnderstandingForRecentEpisodes(from: events)
            let causalEvents = try environment.eventStore.allEvents()
            appendCausalValidation(from: causalEvents)
            let refreshedEvents = try environment.eventStore.allEvents()
            let report = CausalUnderstandingBuilder().report(events: refreshedEvents)
            append(
                .init(
                    type: .causalUnderstandingReport,
                    payload: [
                        "period": "all",
                        "source_event_ids": refreshedEvents.suffix(200).map(\.id.uuidString).joined(separator: ","),
                        "pipeline_version": ObserverPipeline.version
                    ],
                    workspaceTopologyVersion: environment.topology.version
                )
            )
            return try ArtifactExporter(directory: environment.dataDirectory).export(
                name: "causal-understanding-report",
                contents: report
            )
        } catch {
            print("Failed to export causal understanding report: \(error)")
            return nil
        }
    }

    func exportDailyActivityReport(day: Date = Date()) -> URL? {
        do {
            let events = try environment.eventStore.allEvents()
            appendContextFabricForRecentEpisodes(from: events)
            let refreshedEvents = try environment.eventStore.allEvents()
            let result = DailyActivityReportBuilder().build(events: refreshedEvents, day: day)
            append(
                .init(
                    type: .dailyActivityReport,
                    confidence: 0.7,
                    payload: result.diagnostics,
                    workspaceTopologyVersion: environment.topology.version
                )
            )
            return try ArtifactExporter(directory: environment.dataDirectory).export(
                name: "daily-activity-report",
                contents: result.markdown
            )
        } catch {
            print("Failed to export daily activity report: \(error)")
            return nil
        }
    }

    private func appendContextFabricForRecentEpisodes(from events: [ObserverEvent], limit: Int = 50) {
        guard environment.settings.contextFabric.contextFabricEnabled,
              !events.isEmpty,
              !isAppendingContextFabric
        else {
            return
        }
        isAppendingContextFabric = true
        defer { isAppendingContextFabric = false }
        let result = ContextFabricBuilder().build(events: Array(events.suffix(limit * 500)), now: Date())
        if environment.settings.contextFabric.contextLinkerEnabled {
            for payload in result.artifactIdentities {
                append(
                    .init(
                        type: .artifactIdentity,
                        confidence: Double(payload["confidence"] ?? "") ?? 0.75,
                        payload: payload,
                        workspaceTopologyVersion: environment.topology.version
                    )
                )
            }
            for payload in result.artifactTransitions {
                append(
                    .init(
                        type: .artifactTransition,
                        confidence: Double(payload["confidence"] ?? "") ?? 0.5,
                        payload: payload,
                        workspaceTopologyVersion: environment.topology.version
                    )
                )
            }
            for payload in result.activityThreads {
                append(
                    .init(
                        type: .activityThread,
                        confidence: Double(payload["confidence"] ?? "") ?? 0.6,
                        payload: payload,
                        workspaceTopologyVersion: environment.topology.version
                    )
                )
            }
            for payload in result.assignments {
                append(
                    .init(
                        type: .episodeThreadAssignment,
                        confidence: Double(payload["confidence"] ?? "") ?? 0.5,
                        payload: payload,
                        workspaceTopologyVersion: environment.topology.version
                    )
                )
            }
            for payload in result.linkAudits {
                append(
                    .init(
                        type: .contextLinkAudit,
                        confidence: Double(payload["confidence"] ?? "") ?? 0.5,
                        payload: payload,
                        workspaceTopologyVersion: environment.topology.version
                    )
                )
            }
            for payload in result.intentionAnchors {
                append(
                    .init(
                        type: .intentionAnchor,
                        confidence: 0.88,
                        payload: payload,
                        workspaceTopologyVersion: environment.topology.version
                    )
                )
            }
            for payload in result.spanIntentionAssignments {
                append(
                    .init(
                        type: .spanIntentionAssignment,
                        confidence: Double(payload["confidence"] ?? "") ?? 0.5,
                        payload: payload,
                        workspaceTopologyVersion: environment.topology.version
                    )
                )
            }
            for payload in result.chainLinks {
                append(
                    .init(
                        type: .chainLink,
                        confidence: Double(payload["confidence"] ?? "") ?? 0.5,
                        payload: payload,
                        workspaceTopologyVersion: environment.topology.version
                    )
                )
            }
        }
        if environment.settings.contextFabric.activityTrackerEnabled {
            for payload in result.contextSlices {
                append(
                    .init(
                        type: .contextSlice,
                        confidence: Double(payload["coverage"] ?? "") ?? 0.5,
                        payload: payload,
                        workspaceTopologyVersion: environment.topology.version
                    )
                )
            }
        }
    }

    /// This collector has no UI or execution path. It only emits a revised
    /// candidate when a concrete capture-to-transform chain gains evidence.
    private func appendRoutineCandidates(from events: [ObserverEvent]) {
        let candidates = RoutineMiningBuilder(settings: environment.settings.routineMining).build(events: events)
        guard candidates.isEmpty == false else { return }

        let latestSupport = Dictionary(
            grouping: events.filter { $0.type == .routineCandidate },
            by: { $0.payload["routine_key"] ?? "" }
        ).mapValues { candidates in
            candidates.compactMap { Int($0.payload["completion_count"] ?? "") }.max() ?? 0
        }

        for candidate in candidates where candidate.completionCount > (latestSupport[candidate.routineKey] ?? 0) {
            append(
                .init(
                    type: .routineCandidate,
                    confidence: candidate.confidence,
                    payload: candidate.payload,
                    workspaceTopologyVersion: environment.topology.version
                )
            )
        }
    }

    private func appendCausalUnderstandingForRecentEpisodes(from events: [ObserverEvent], limit: Int = 25) {
        let alreadyProcessed = Set(events.filter { event in
            event.type == .causalHypothesis || event.type == .stateTransition
        }.compactMap { $0.payload["episode_event_id"] })
        let eventByID = Dictionary(events.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { _, newer in newer })
        let iso = ISO8601DateFormatter()
        let builder = CausalUnderstandingBuilder()

        for episode in events.filter({ $0.type == .episode }).suffix(limit) where !alreadyProcessed.contains(episode.id.uuidString) {
            let traceIDs = (episode.payload["trace_event_ids"] ?? episode.payload["source_event_ids"] ?? "")
                .split(separator: ",")
                .map(String.init)
            var episodeEvents = traceIDs.compactMap { eventByID[$0] }
            if episodeEvents.isEmpty,
               let start = iso.date(from: episode.payload["start"] ?? ""),
               let end = iso.date(from: episode.payload["end"] ?? "") {
                episodeEvents = events.filter { event in
                    event.timestamp >= start
                        && event.timestamp <= end
                        && event.id != episode.id
                }
            }
            guard !episodeEvents.isEmpty else {
                continue
            }
            let result = builder.buildForClosedEpisode(
                episode: episode,
                episodeEvents: episodeEvents,
                historicalEvents: events,
                now: Date()
            )
            for payload in result.evidence {
                append(
                    .init(
                        type: .evidence,
                        confidence: Double(payload["reliability"] ?? "") ?? 0.5,
                        payload: payload,
                        workspaceTopologyVersion: environment.topology.version
                    )
                )
            }
            for payload in result.transitions {
                append(
                    .init(
                        type: .stateTransition,
                        confidence: Double(payload["confidence"] ?? "") ?? 0.5,
                        payload: payload,
                        workspaceTopologyVersion: environment.topology.version
                    )
                )
            }
            for payload in result.antecedents {
                let confidence = ((Double(payload["semantic_relevance"] ?? "") ?? 0.5)
                    + (Double(payload["temporal_relevance"] ?? "") ?? 0.5)) / 2
                append(
                    .init(
                        type: .causalAntecedent,
                        confidence: confidence,
                        payload: payload,
                        workspaceTopologyVersion: environment.topology.version
                    )
                )
            }
            for payload in result.hypotheses {
                append(
                    .init(
                        type: .causalHypothesis,
                        confidence: Double(payload["confidence"] ?? "") ?? 0.5,
                        payload: payload,
                        workspaceTopologyVersion: environment.topology.version
                    )
                )
            }
        }
    }

    func localInsight(forLast interval: TimeInterval) -> String {
        let now = Date()
        if let cached = localInsightCache,
           cached.interval == interval,
           now.timeIntervalSince(cached.createdAt) < 8 {
            return cached.text
        }
        let cutoff = interval > 0
            ? now.addingTimeInterval(-interval)
            : Calendar.current.startOfDay(for: now)
        let sourceEvents = interval <= 0
            ? ((try? environment.eventStore.allEvents()) ?? [])
            : ((try? environment.eventStore.recentEvents(limit: 5_000)) ?? [])
        let events = sourceEvents
            .filter { $0.timestamp >= cutoff }
        guard !events.isEmpty else {
            return "За этот интервал пока нет наблюдений."
        }

        let securityLine = securityIncidentInsightLine()
        let state = cleanInsightFragment(events.reversed().first { $0.type == .cognitiveState }?.payload["state"])
        let intervalLabel = insightIntervalLabel(interval)

        let text = [
            securityLine,
            "\(intervalLabel): \(semanticFocusSummary(events))",
            cameraCandidateSummary(events),
            episodeSpanSummary(events),
            contextShiftSummary(events),
            latestContentSummary(events),
            state.map { "Состояние: \($0)" },
            latestReactionSummary(events)
        ]
        .compactMap { $0 }
        .prefix(5)
        .joined(separator: "\n")
        localInsightCache = (interval, now, text)
        return text
    }

    func markSecurityIncidentsSeen() {
        environment.securityIncidentStore.markAllSeen()
        notifyStateChanged()
    }

    func recordManualGazeCalibration(
        displayIndex: Int,
        cellIndex: Int,
        predictedDisplayIndex: Int?,
        predictedCellIndex: Int?
    ) {
        var payload: [String: String] = [
            "target_source": "guided_pill_calibration",
            "sample_mode": "prompted_target_enter",
            "actual_display_index": "\(displayIndex)",
            "actual_cell_index": "\(cellIndex)",
            "prediction_correct": predictedDisplayIndex == displayIndex && predictedCellIndex == cellIndex ? "true" : "false"
        ]
        if let predictedDisplayIndex {
            payload["predicted_display_index"] = "\(predictedDisplayIndex)"
        }
        if let predictedCellIndex {
            payload["predicted_cell_index"] = "\(predictedCellIndex)"
        }
        if let attention = smoothedAttentionForDisplay {
            payload.merge(attention.eventPayload) { current, _ in current }
        }
        append(
            .init(
                type: .gazeCalibrationSample,
                confidence: 0.9,
                payload: payload,
                workspaceTopologyVersion: environment.topology.version
            )
        )
        notifyStateChanged()
    }

    func recordCalibrationSessionAction(_ action: String) {
        append(
            .init(
                type: .gazeCalibrationSample,
                confidence: 1,
                payload: [
                    "target_source": "manual_pill_calibration_session",
                    "action": action
                ],
                workspaceTopologyVersion: environment.topology.version
            )
        )
        notifyStateChanged()
    }

    func latestSecurityIncidentArtifactURL() -> URL? {
        let incident = environment.securityIncidentStore.latestReviewable()
        return incident?.photoURL
            ?? incident?.screenshotURL
            ?? incident?.transcriptURL
            ?? environment.securityIncidentStore.directoryURL
    }

    private func securityIncidentInsightLine() -> String? {
        guard let incident = environment.securityIncidentStore.latestUnseen() else {
            return nil
        }
        let photo = incident.photoURL == nil ? "фото нет" : "фото сохранено"
        let screen = incident.screenshotURL == nil ? "скрин нет" : "скрин сохранён"
        let transcript = incident.transcriptURL == nil ? "транскрипт нет" : "транскрипт сохранён"
        return "Защита: \(incident.summary) \(screen); \(transcript); аудио пока не записывалось; \(photo)."
    }

    private func semanticFocusSummary(_ events: [ObserverEvent]) -> String {
        if let content = latestContentSummary(events)?.replacingOccurrences(of: "Контекст: ", with: "") {
            return content
        }

        let topApps = topFocusApps(events, limit: 3)
        guard !topApps.isEmpty else {
            return "нет устойчивой рабочей линии"
        }

        let names = topApps.map(\.name)
        let lowerNames = names.map { $0.lowercased() }
        let hasAIChat = lowerNames.contains { name in
            name.contains("chatgpt") || name.contains("claude") || name.contains("gemini") || name.contains("codex")
        }
        let hasDesign = lowerNames.contains { name in
            name.contains("figma") || name.contains("sketch")
        }

        if hasAIChat, hasDesign {
            return "связка ИИ + дизайн: уточняешь задачу и сверяешь визуальный результат"
        }

        if let first = topApps.first {
            let tail = topApps.dropFirst().first.map { "; рядом \($0.name) \(formatCompactDuration($0.seconds))" } ?? ""
            return "основная линия \(first.name) \(formatCompactDuration(first.seconds))\(tail)"
        }

        return names.joined(separator: " + ")
    }

    private func cameraCandidateSummary(_ events: [ObserverEvent]) -> String? {
        let cameraCues = events.filter { event in
            event.type == .behaviorCue
                && event.payload["detector_tier"] == "tier1"
                && event.payload["cascade_stage"] == "tier1_candidate"
        }
        if let yawn = cameraCues.reversed().first(where: { $0.payload["cue"] == "energy_drop_candidate" }) {
            let score = yawn.payload["mouth_open_score"].map { " score \($0)" } ?? ""
            return "Камера: зевок пойман как кандидат\(score); в вывод не идёт без PERCLOS/ритма."
        }
        if let smile = cameraCues.reversed().first(where: { $0.payload["cue"] == "positive_reaction_candidate" }) {
            let score = smile.payload["smile_score"].map { " score \($0)" } ?? ""
            return "Камера: улыбка только кандидат\(score); нужна связка с контекстом."
        }
        return nil
    }

    private func episodeSpanSummary(_ events: [ObserverEvent]) -> String? {
        guard let span = events.reversed().first(where: { $0.type == .attentionSpan }) else {
            return nil
        }
        let kind = readableSpanKind(span.payload["span_kind"])
        let apps = cleanInsightFragment(span.payload["apps"], allowShortCodeLikeText: false)
        let switches = span.payload["switches_within_span"]
        let duration = Double(span.payload["duration_seconds"] ?? "").map(formatCompactDuration)
        let details = [
            apps.map { "через \($0)" },
            duration.map { "\($0)" },
            switches.map { "переходов внутри связки \($0)" }
        ].compactMap { $0 }.joined(separator: " · ")
        return details.isEmpty ? "Эпизод: \(kind)" : "Эпизод: \(kind) · \(details)"
    }

    private func contextShiftSummary(_ events: [ObserverEvent]) -> String? {
        let focusEvents = events
            .filter { $0.type == .appFocus || $0.type == .appFocusInterval }
            .compactMap { cleanInsightFragment($0.payload["app_name"]) }
        let uniqueApps = Array(NSOrderedSet(array: focusEvents).compactMap { $0 as? String })
        guard uniqueApps.count >= 2 else {
            return nil
        }

        if uniqueApps.count >= 4 {
            let route = uniqueApps.prefix(4).joined(separator: " -> ")
            return "Сдвиг: много переходов (\(route)); проверь, не потерялась ли главная линия."
        }

        let route = uniqueApps.prefix(3).joined(separator: " -> ")
        return "Сдвиг: \(route); контекст не один, важно удержать главный артефакт."
    }

    private func latestContentSummary(_ events: [ObserverEvent]) -> String? {
        guard let event = events.reversed().first(where: { $0.type == .contentContext }) else {
            return nil
        }
        let app = cleanInsightFragment(event.payload["app_name"]) ?? "текущий экран"
        let kind = event.payload["content_kind"].map(readableContentKind) ?? "контент"
        let topic = cleanInsightFragment(event.payload["topic"], allowShortCodeLikeText: false)
        let sentiment = event.payload["sentiment"].flatMap(readableSentiment)
        let details = [kind, topic, sentiment].compactMap { $0 }.joined(separator: " · ")
        guard !details.isEmpty else {
            return "Контекст: \(app)"
        }
        return "Контекст: \(app): \(details)"
    }

    private func latestReactionSummary(_ events: [ObserverEvent]) -> String? {
        guard let event = events.reversed().first(where: { event in
            event.type == .boundReaction || event.type == .behaviorCue
        }) else {
            return nil
        }

        let raw = event.payload["interpretation"]
            ?? event.payload["cue"]
            ?? event.payload["activity_insight"]
            ?? event.payload["insight"]
        guard let value = raw else {
            return nil
        }
        return "Реакция: \(readableCue(value))"
    }

    private func appendReadinessReports(from events: [ObserverEvent], now: Date = Date()) {
        let builder = ReadinessReportBuilder(settings: environment.settings.readinessSettings)
        let funnel = builder.funnelReport(events: events, now: now)
        append(
            .init(
                type: .funnelReport,
                payload: funnel.payload,
                workspaceTopologyVersion: environment.topology.version
            )
        )
        let audit = builder.fusionAudit(events: events, now: now)
        append(
            .init(
                type: .fusionAudit,
                payload: audit.payload,
                workspaceTopologyVersion: environment.topology.version
            )
        )
        let readiness = builder.readinessReport(events: events, now: now)
        append(
            .init(
                type: .readinessReport,
                payload: readiness.payload,
                workspaceTopologyVersion: environment.topology.version
            )
        )
        appendCausalValidation(from: events, now: now)
    }

    private func appendCausalValidation(from events: [ObserverEvent], now: Date = Date()) {
        let result = CausalUnderstandingBuilder().validationReport(events: events, now: now)
        append(
            .init(
                type: .causalValidationReport,
                payload: result.payload,
                workspaceTopologyVersion: environment.topology.version
            )
        )
        for pattern in result.patterns {
            append(
                .init(
                    type: .personalCausalPattern,
                    confidence: Double(pattern["confidence"] ?? "") ?? 0.5,
                    payload: pattern,
                    workspaceTopologyVersion: environment.topology.version
                )
            )
        }
    }

    private func buildReadinessMarkdown(events: [ObserverEvent], now: Date = Date()) -> String {
        let builder = ReadinessReportBuilder(settings: environment.settings.readinessSettings)
        let funnel = builder.funnelReport(events: events, now: now)
        let audit = builder.fusionAudit(events: events, now: now)
        let readiness = builder.readinessReport(events: events, now: now)
        return """
        # Observer Readiness Report

        \(readiness.markdown)

        \(funnel.markdown)

        \(audit.markdown)

        ## Rule

        Predictions and proactive suggestions stay blocked until every readiness gate is green.
        """
    }

    private func topFocusApps(_ events: [ObserverEvent], limit: Int) -> [(name: String, seconds: Double)] {
        var durations: [String: Double] = [:]
        var counts: [String: Int] = [:]

        for event in events where event.type == .appFocusInterval || event.type == .appFocus {
            guard let app = cleanInsightFragment(event.payload["app_name"]) else {
                continue
            }
            counts[app, default: 0] += 1
            if event.type == .appFocusInterval {
                durations[app, default: 0] += Double(event.payload["duration_seconds"] ?? "") ?? 0
            }
        }

        if !durations.isEmpty {
            return durations
                .sorted { $0.value > $1.value }
                .prefix(limit)
                .map { (name: $0.key, seconds: $0.value) }
        }

        return counts
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (name: $0.key, seconds: Double($0.value * 60)) }
    }

    private func readableContentKind(_ kind: String) -> String {
        switch kind {
        case "prompt":
            return "диалог с ИИ"
        case "message":
            return "сообщения"
        case "email":
            return "почта"
        case "code":
            return "код"
        case "doc":
            return "документ"
        case "video":
            return "видео"
        case "article":
            return "страница"
        default:
            return kind
        }
    }

    private func readableSpanKind(_ kind: String?) -> String {
        switch kind {
        case "ai_assisted_design":
            return "ИИ помогает довести дизайн"
        case "ai_assisted_work":
            return "ИИ-итерация по рабочей задаче"
        case "design_work":
            return "дизайн-работа"
        case "communication":
            return "переписка с рабочим следом"
        case "reading_research":
            return "исследование и чтение"
        case "mixed":
            return "смешанный рабочий фрагмент"
        default:
            return "рабочий фрагмент"
        }
    }

    private func readableSentiment(_ sentiment: String) -> String? {
        switch sentiment {
        case "neg":
            return "негативный тон"
        case "pos":
            return "позитивный тон"
        case "mixed":
            return "смешанный тон"
        default:
            return nil
        }
    }

    private func readableCue(_ cue: String) -> String {
        let lower = cue.lowercased()
        if lower.contains("positive") || lower.contains("smile") {
            return "позитивная реакция в текущем контексте"
        }
        if lower.contains("yawn") || lower.contains("fatigue") || lower.contains("energy") {
            return "просадка энергии, стоит снизить размер следующего шага"
        }
        if lower.contains("friction") || lower.contains("strong_reaction") || lower.contains("sharp") {
            return "фрикция: заметный резкий сдвиг поведения"
        }
        if lower.contains("context") || lower.contains("switch") {
            return "переключение контекста"
        }
        return cleanInsightFragment(cue, allowShortCodeLikeText: false) ?? cue
    }

    private func focusDistributionSummary(_ events: [ObserverEvent]) -> String {
        var durations: [String: Double] = [:]
        var counts: [String: Int] = [:]

        for event in events where event.type == .appFocusInterval || event.type == .appFocus {
            guard let app = cleanInsightFragment(event.payload["app_name"]) else {
                continue
            }
            counts[app, default: 0] += 1
            if event.type == .appFocusInterval {
                durations[app, default: 0] += Double(event.payload["duration_seconds"] ?? "") ?? 0
            }
        }

        if !durations.isEmpty {
            let top = durations
                .sorted { $0.value > $1.value }
                .prefix(2)
                .map { "\($0.key) \(formatCompactDuration($0.value))" }
                .joined(separator: " · ")
            if !top.isEmpty {
                return top
            }
        }

        let top = counts
            .sorted { $0.value > $1.value }
            .prefix(2)
            .map { "\($0.key) ×\($0.value)" }
            .joined(separator: " · ")
        return top.isEmpty ? "контекст неясен" : top
    }

    private func formatCompactDuration(_ seconds: Double) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 {
            return "\(minutes)м"
        }
        return "\(minutes / 60)ч\(minutes % 60 == 0 ? "" : " \(minutes % 60)м")"
    }

    private func insightIntervalLabel(_ interval: TimeInterval) -> String {
        if interval <= 0 {
            return "За сегодня"
        }
        let minutes = Int(interval / 60)
        if minutes < 60 {
            return "За \(minutes)м"
        }
        return "За \(minutes / 60)ч"
    }

    private func cleanInsightFragment(_ value: String?, allowShortCodeLikeText: Bool = true) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if trimmed.count > 80 {
            return nil
        }
        if !allowShortCodeLikeText, looksLikeScrapedChromeTitle(trimmed) {
            return nil
        }
        if !allowShortCodeLikeText, trimmed.contains("•") {
            return nil
        }
        let letters = trimmed.filter(\.isLetter).count
        let digits = trimmed.filter(\.isNumber).count
        let separators = trimmed.filter { $0.isWhitespace || ",.:;!?/()-".contains($0) }.count
        let other = max(0, trimmed.count - letters - digits - separators)
        if !allowShortCodeLikeText, other > 2 {
            return nil
        }
        if letters > 0, digits > letters * 2 {
            return nil
        }
        if trimmed.range(of: #"[A-Za-z0-9+/]{12,}"#, options: .regularExpression) != nil {
            return nil
        }
        return trimmed
    }

    private func looksLikeScrapedChromeTitle(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower.contains("google inbox") || lower.contains("whatc") || lower.contains("telegram") {
            return true
        }
        if value.contains(" | "), value.contains(" - ") {
            return true
        }
        if value.hasPrefix("("), value.contains(":") {
            return true
        }
        return false
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
        let context = ContextPackBuilder(
            topology: environment.topology,
            pseudonymizeEntities: environment.settings.pseudonymizeEntities,
            entityAggregates: (try? environment.entityStore.aggregates()) ?? [:]
        ).build(events: events, mode: mode)

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
            try GeminiKeyStore(directory: environment.dataDirectory).setAPIKey(trimmed)
            append(
                .init(
                    type: .geminiKeyUpdated,
                    payload: ["storage": "local_private_file"],
                    workspaceTopologyVersion: environment.topology.version
                )
            )
            print("Gemini API key saved locally for Observer.")
        } catch {
            print("Failed to save Gemini API key: \(error)")
        }
    }

    func deleteGeminiAPIKey() {
        GeminiKeyStore(directory: environment.dataDirectory).deleteAPIKey()
        append(
            .init(
                type: .geminiKeyDeleted,
                payload: ["storage": "local_private_file"],
                workspaceTopologyVersion: environment.topology.version
            )
        )
        print("Gemini API key deleted.")
    }

    func generateGeminiInsight() {
        requestGeminiInsight(requestKind: "work_insight", widgetMode: false, copyToPasteboard: true)
    }

    private func requestGeminiInsight(
        requestKind: String,
        widgetMode: Bool,
        copyToPasteboard: Bool
    ) {
        guard environment.settings.geminiEnabled else {
            print("Gemini is disabled in Observer settings.")
            return
        }

        let apiKey = GeminiKeyStore(directory: environment.dataDirectory)
            .apiKey(allowKeychainMigration: false)

        guard let apiKey, !apiKey.isEmpty else {
            recordGeminiKeyStatusIfChanged()
            print("Gemini API key is not configured. Use Set Gemini API Key first.")
            return
        }
        recordGeminiKeyStatusIfChanged()

        let isDailyMode = requestKind == "daily_patterns"
        let events = (try? environment.eventStore.recentEvents(limit: isDailyMode ? 2500 : 500)) ?? []
        appendDetectorEvents(from: events)
        let context = ContextPackBuilder(
            topology: environment.topology,
            pseudonymizeEntities: environment.settings.pseudonymizeEntities,
            entityAggregates: (try? environment.entityStore.aggregates()) ?? [:]
        ).build(events: events, mode: mode)
        let digest = ResearchDigestBuilder().build(events: events)
        let attention = stateSnapshot.attentionText
        let prompt: String
        if isDailyMode {
            prompt = GeminiInsightProvider.buildDailyPrompt(context: context, digest: digest, attention: attention)
        } else if widgetMode {
            prompt = GeminiInsightProvider.buildWidgetPrompt(context: context, digest: digest, attention: attention)
        } else {
            prompt = GeminiInsightProvider.buildPrompt(context: context, digest: digest, attention: attention)
        }
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
                        "request_kind": requestKind,
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
                    "request_kind": requestKind,
                    "status": "started",
                    "prompt_chars": "\(prompt.count)",
                    "request_body": prompt,
                    "pseudonymize_entities": environment.settings.pseudonymizeEntities ? "true" : "false",
                    "estimated_cost_eur": String(format: "%.4f", environment.settings.geminiEstimatedCostPerRequestEUR),
                    "spent_today_eur": String(format: "%.4f", budgetDecision.spentTodayEUR),
                    "daily_budget_eur": String(format: "%.2f", budgetDecision.budgetEUR)
                ],
                workspaceTopologyVersion: environment.topology.version
            )
        )

        Task {
            do {
                let provider = GeminiInsightProvider(
                    apiKey: apiKey,
                    model: model
                )
                let insight: String
                if isDailyMode {
                    insight = try await provider.generateDailyInsight(context: context, digest: digest, attention: attention)
                } else if widgetMode {
                    insight = try await provider.generateWidgetInsight(context: context, digest: digest, attention: attention)
                } else {
                    insight = try await provider.generateInsight(context: context, digest: digest, attention: attention)
                }

                await MainActor.run {
                    let sourceEventIDs = events.suffix(24).map(\.id.uuidString).joined(separator: ",")
                    var payload: [String: String] = [
                        "provider": "gemini",
                        "model": model,
                        "model_version": model,
                        "prompt_version": isDailyMode ? "daily_patterns_v2" : (widgetMode ? "widget_sensemaking_v2" : "work_insight_v2"),
                        "request_kind": requestKind,
                        "insight": insight,
                        "source_event_ids": sourceEventIDs,
                        "abstraction_level": widgetMode ? "L2" : "L3",
                        "primary_source_type": "context_pack"
                    ]
                    if widgetMode {
                        payload["widget_line"] = insight
                        let event = ObserverEvent(
                            type: .geminiInsight,
                            payload: payload,
                            workspaceTopologyVersion: self.environment.topology.version
                        )
                        let enriched = self.lineagePayload(for: event, payload: payload)
                        if UserVisibleOutputPolicy.validate(payload: enriched) == .allowed {
                            self.setLatestContextLine(insight)
                        }
                    }
                    self.append(
                        .init(
                            type: .geminiInsight,
                            payload: payload,
                            workspaceTopologyVersion: self.environment.topology.version
                        )
                    )
                    if copyToPasteboard {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(insight, forType: .string)
                    }
                    print(insight)
                    self.notifyStateChanged()
                }
            } catch {
                await MainActor.run {
                    self.append(
                        .init(
                            type: .externalLLMRequest,
                            payload: [
                                "provider": "gemini",
                                "model": model,
                                "request_kind": requestKind,
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
        let status = scheduleGate.status(at: event.timestamp)
        guard status.sensorAllowed || event.type.isOperationalOutsideSchedule else {
            return
        }
        var payload = lineagePayload(for: event, payload: event.payload)
        if status.outsideDefaultSchedule {
            payload["outside_default_schedule"] = "true"
        }
        let eventToWrite = ObserverEvent(
            id: event.id,
            timestamp: event.timestamp,
            type: event.type,
            source: event.source,
            platform: event.platform,
            displayRole: event.displayRole,
            appID: event.appID,
            confidence: event.confidence,
            payload: payload,
            workspaceTopologyVersion: event.workspaceTopologyVersion
        )
        do {
            try environment.eventStore.append(eventToWrite)
        } catch {
            print("Failed to write event: \(error)")
        }
    }

    private func lineagePayload(for event: ObserverEvent, payload: [String: String]) -> [String: String] {
        guard event.type.requiresLineage else {
            return payload
        }

        var enriched = payload
        enriched["pipeline_version"] = enriched["pipeline_version"] ?? ObserverPipeline.version
        enriched["created_at"] = enriched["created_at"] ?? ISO8601DateFormatter().string(from: event.timestamp)
        enriched["session_id"] = enriched["session_id"] ?? currentSessionID ?? "no_active_session"
        enriched["episode_id"] = enriched["episode_id"] ?? currentEpisodeID ?? "no_active_episode"
        enriched["valid_until"] = enriched["valid_until"] ?? ISO8601DateFormatter().string(
            from: event.timestamp.addingTimeInterval(30 * 60)
        )

        if enriched["source_event_ids"] == nil {
            if let trace = enriched["trace_event_ids"], !trace.isEmpty {
                enriched["source_event_ids"] = trace
            } else if let evidence = enriched["evidence_event_ids"], !evidence.isEmpty {
                enriched["source_event_ids"] = evidence
            } else if let candidate = enriched["candidate_event_id"], !candidate.isEmpty {
                enriched["source_event_ids"] = candidate
            } else {
                enriched["source_event_ids"] = ""
                enriched["lineage_status"] = "missing_source_events"
            }
        }

        if event.type.isUserVisibleCandidate {
            let decision = UserVisibleOutputPolicy.validate(payload: enriched)
            enriched["user_visible_policy"] = decision.rawValue
            if decision != .allowed {
                enriched["surfaced_in_widget"] = "false"
            }
        }

        return enriched
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
                minimumEmitInterval: environment.settings.attentionSampleIntervalSeconds,
                smileCandidateThreshold: environment.settings.cameraDetectorSettings.tier1SmileCandidateThreshold,
                mouthOpenCandidateThreshold: environment.settings.cameraDetectorSettings.tier1MouthOpenCandidateThreshold
            ) { [weak self] snapshot in
                self?.handleAttentionSnapshot(snapshot)
            }
            append(
                .init(
                    type: .cameraAttentionStarted,
                    payload: [
                        "sample_interval_seconds": "\(Int(environment.settings.attentionSampleIntervalSeconds))",
                        "detector_pipeline": "tier1_media_pipe_vision_plus_tier2_openface_shadow",
                        "tier1_smile_candidate_threshold": String(format: "%.2f", environment.settings.cameraDetectorSettings.tier1SmileCandidateThreshold),
                        "tier1_mouth_open_candidate_threshold": String(format: "%.2f", environment.settings.cameraDetectorSettings.tier1MouthOpenCandidateThreshold),
                        "tier2_sidecar_enabled": environment.settings.cameraDetectorSettings.tier2SidecarEnabled ? "true" : "false",
                        "cascade_shadow_mode": environment.settings.cameraDetectorSettings.cascadeShadowMode ? "true" : "false"
                    ],
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
                let shouldSurfaceHint = false

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

    private func recordAttentionSpanIfNeeded(currentFocusEvent: ObserverEvent) {
        // Spans can bridge a short sequence of tool changes; 40 events was too
        // shallow to see that sequence once camera and input telemetry were present.
        var events = (try? environment.eventStore.recentEvents(limit: 120)) ?? []
        if events.last?.id != currentFocusEvent.id {
            events.append(currentFocusEvent)
        }
        guard let span = AttentionSpanBuilder().build(from: events, now: Date()),
              span.signature != lastAttentionSpanSignature
        else {
            return
        }

        lastAttentionSpanSignature = span.signature
        append(
            .init(
                type: .attentionSpan,
                appID: currentFocusEvent.appID,
                confidence: span.confidence,
                payload: span.payload,
                workspaceTopologyVersion: environment.topology.version
            )
        )
    }

    private func closeCurrentEpisode(outcome: String, now: Date = Date()) {
        guard let start = currentEpisodeStartedAt else {
            currentEpisodeStartedAt = now
            return
        }

        defer {
            currentEpisodeStartedAt = now
            currentEpisodeID = UUID().uuidString
        }

        let events = ((try? environment.eventStore.recentEvents(limit: 2_000)) ?? [])
            .filter { $0.timestamp >= start && $0.timestamp <= now }
        guard let episode = EpisodeBuilder().build(
            events: events,
            start: start,
            end: now,
            outcome: outcome
        ) else {
            appendDegradedEpisodeClose(start: start, end: now, outcome: outcome, events: events, reason: events.isEmpty ? "empty_lineage" : "partial_lineage")
            return
        }

        let episodeEvent = ObserverEvent(
            type: .episode,
            confidence: episode.confidence,
            payload: episode.payload,
            workspaceTopologyVersion: environment.topology.version
        )
        append(episodeEvent)

        let historicalEvents = (try? environment.eventStore.recentEvents(limit: 8_000)) ?? events
        // Context and causal interpretation are optional enrichment. A malformed
        // lineage must never take down the sensor process that just closed work.
        guard !events.isEmpty else {
            appendDegradedEpisodeClose(start: start, end: now, outcome: outcome, events: events, reason: "empty_lineage_after_build")
            return
        }
        appendContextFabricForRecentEpisodes(from: historicalEvents + [episodeEvent], limit: 10)
        appendRoutineCandidates(from: historicalEvents + [episodeEvent])
        let causal = CausalUnderstandingBuilder().buildForClosedEpisode(
            episode: episodeEvent,
            episodeEvents: events,
            historicalEvents: historicalEvents,
            now: now
        )
        for payload in causal.evidence {
            append(
                .init(
                    type: .evidence,
                    confidence: Double(payload["reliability"] ?? "") ?? 0.5,
                    payload: payload,
                    workspaceTopologyVersion: environment.topology.version
                )
            )
        }
        for payload in causal.transitions {
            append(
                .init(
                    type: .stateTransition,
                    confidence: Double(payload["confidence"] ?? "") ?? 0.5,
                    payload: payload,
                    workspaceTopologyVersion: environment.topology.version
                )
            )
        }
        for payload in causal.antecedents {
            let confidence = ((Double(payload["semantic_relevance"] ?? "") ?? 0.5)
                + (Double(payload["temporal_relevance"] ?? "") ?? 0.5)) / 2
            append(
                .init(
                    type: .causalAntecedent,
                    confidence: confidence,
                    payload: payload,
                    workspaceTopologyVersion: environment.topology.version
                )
            )
        }
        for payload in causal.hypotheses {
            append(
                .init(
                    type: .causalHypothesis,
                    confidence: Double(payload["confidence"] ?? "") ?? 0.5,
                    payload: payload,
                    workspaceTopologyVersion: environment.topology.version
                )
            )
        }
    }

    private func appendDegradedEpisodeClose(
        start: Date,
        end: Date,
        outcome: String,
        events: [ObserverEvent],
        reason: String
    ) {
        let sourceIDs = events.suffix(40).map { $0.id.uuidString }.joined(separator: ",")
        append(
            .init(
                type: .episode,
                confidence: 0.2,
                payload: [
                    "episode_id": UUID().uuidString,
                    "status": "degraded_close",
                    "degraded_reason": reason,
                    "outcome": outcome,
                    "start": ISO8601DateFormatter().string(from: start),
                    "end": ISO8601DateFormatter().string(from: end),
                    "duration_seconds": String(format: "%.1f", end.timeIntervalSince(start)),
                    "source_event_ids": sourceIDs
                ],
                workspaceTopologyVersion: environment.topology.version
            )
        )
    }

    // Presence is deliberately broader than "face in this one frame": reading
    // and typing can briefly hide the face, while an old cursor heartbeat must
    // not turn an empty chair into an active work episode.
    private func isPresenceActive(now: Date = Date()) -> Bool {
        guard let lastConfirmedPresenceAt else { return false }
        return now.timeIntervalSince(lastConfirmedPresenceAt) <= 120
    }

    private func updatePresence(
        facePresent: Bool,
        input: InputActivitySnapshot?,
        now: Date
    ) {
        var confirmedAt: Date?
        if facePresent {
            confirmedAt = now
        }
        if let input, input.secondsSinceAnyInput <= 120 {
            let inputAt = now.addingTimeInterval(-max(0, input.secondsSinceAnyInput))
            confirmedAt = max(confirmedAt ?? .distantPast, inputAt)
        }

        if let confirmedAt {
            let wasAway = awayStartedAt != nil
            lastConfirmedPresenceAt = max(lastConfirmedPresenceAt ?? .distantPast, confirmedAt)
            guard wasAway else { return }

            let startedAt = awayStartedAt ?? confirmedAt
            let duration = max(0, now.timeIntervalSince(startedAt))
            awayStartedAt = nil
            let closedEpisode = awayEpisodeClosed
            awayEpisodeClosed = false
            if closedEpisode {
                append(
                    .init(
                        type: .observationGap,
                        confidence: 0.95,
                        payload: [
                            "channel": "presence",
                            "reason": "away",
                            "duration_seconds": String(format: "%.1f", duration),
                            "start": ISO8601DateFormatter().string(from: startedAt),
                            "end": ISO8601DateFormatter().string(from: now),
                            "excluded_from_tasks": "true"
                        ],
                        workspaceTopologyVersion: environment.topology.version
                    )
                )
                currentEpisodeStartedAt = now
                currentEpisodeID = UUID().uuidString
                if currentFocus != nil {
                    currentFocusStartedAt = now
                }
            }
            return
        }

        guard let lastConfirmedPresenceAt,
              now.timeIntervalSince(lastConfirmedPresenceAt) >= 180,
              awayStartedAt == nil
        else {
            return
        }

        awayStartedAt = lastConfirmedPresenceAt
        closeCurrentEpisode(outcome: "away", now: now)
        currentEpisodeStartedAt = nil
        closeCurrentFocusInterval(reason: "away")
        currentFocusStartedAt = nil
        awayEpisodeClosed = true
        append(
            .init(
                type: .sessionBoundary,
                confidence: 0.95,
                payload: [
                    "boundary": "away_started",
                    "presence_grace_seconds": "120",
                    "away_close_seconds": "180",
                    "excluded_from_tasks": "true"
                ],
                workspaceTopologyVersion: environment.topology.version
            )
        )
    }

    private func handleAttentionSnapshot(_ snapshot: AttentionSnapshot) {
        let previousAttention = latestAttention
        let previousAttentionAt = latestAttentionAt
        let missingFaceSamplesBeforeCurrent = consecutiveMissingFaceSamples
        let now = Date()
        let hadConfirmedPresenceBeforeCurrent = lastConfirmedPresenceAt != nil
        let confirmedAwayBeforeCurrent = awayStartedAt != nil
            || (hadConfirmedPresenceBeforeCurrent && !isPresenceActive(now: now))
        latestAttention = snapshot
        latestAttentionAt = now
        updatePresence(facePresent: snapshot.facePresent, input: nil, now: now)
        if snapshot.facePresent {
            lastFacePresentAttention = snapshot
            consecutiveMissingFaceSamples = 0
        } else {
            consecutiveMissingFaceSamples += 1
        }
        latestCameraStatus = nil
        recordCameraHealth(snapshot, now: now)
        // A camera frame without a person is useful only for health and the
        // absence boundary. It must not keep a task, mood, or episode alive.
        guard isPresenceActive(now: now) else {
            notifyStateChanged()
            return
        }
        if shouldPersistCameraAttention(snapshot, now: now) {
            let attentionEvent = ObserverEvent(
                type: .attention,
                confidence: snapshot.confidence,
                payload: snapshot.eventPayload,
                workspaceTopologyVersion: environment.topology.version
            )
            append(attentionEvent)
            recordCameraEvidenceIfNeeded(from: attentionEvent, now: now)
        }
        recordVisualObjectEvidenceIfNeeded(snapshot, now: now)
        recordBehaviorCueIfNeeded(
            previousAttention: previousAttention,
            currentAttention: snapshot,
            secondsSincePreviousAttention: previousAttentionAt.map { now.timeIntervalSince($0) },
            now: now
        )
        recordSmileCueIfNeeded(snapshot, now: now)
        recordYawnCueIfNeeded(snapshot, now: now)
        recordAwayPresenceIncidentIfNeeded(
            currentAttention: snapshot,
            missingFaceSamplesBeforeCurrent: missingFaceSamplesBeforeCurrent,
            confirmedAwayBeforeCurrent: confirmedAwayBeforeCurrent,
            now: now
        )
        releaseSecurityIncidentsIfOwnerReturned(now: now)
        commitPendingAwayPresenceIncidentIfNeeded(now: now)
        updateOwnerFaceProfileIfNeeded(snapshot)
        recordGazeCalibrationSampleIfNeeded(now: now)
        recordCognitiveStateOnCadence(now: now)
        updateHeadphoneWearState(from: snapshot, now: now)
        pauseMediaIfUserAppearsAway()
        resumeMediaIfUserReturned()
        notifyStateChanged()
    }

    private func recordCameraEvidenceIfNeeded(from attentionEvent: ObserverEvent, now: Date = Date()) {
        guard environment.settings.contextFabric.cameraEvidenceEnabled else {
            return
        }
        let payloads = ContextFabricBuilder().cameraEvidencePayloads(from: attentionEvent, now: now)
        let signature = payloads
            .map { "\($0["evidence_type"] ?? "unknown"):\($0["label"] ?? "unknown")" }
            .sorted()
            .joined(separator: "|")
        let minimumInterval = environment.settings.contextFabric.cameraEvidenceMinimumIntervalSeconds
        guard signature != lastCameraEvidenceSignature
            || lastCameraEvidenceAt.map({ now.timeIntervalSince($0) >= minimumInterval }) ?? true
        else {
            return
        }
        lastCameraEvidenceSignature = signature
        lastCameraEvidenceAt = now
        for payload in payloads {
            guard (Double(payload["confidence"] ?? "") ?? attentionEvent.confidence) >= environment.settings.contextFabric.cameraEvidenceMinimumConfidence else {
                continue
            }
            append(
                .init(
                    type: .cameraEvidence,
                    confidence: Double(payload["confidence"] ?? "") ?? attentionEvent.confidence,
                    payload: payload,
                    workspaceTopologyVersion: environment.topology.version
                )
            )
        }
    }

    private func shouldPersistCameraAttention(_ snapshot: AttentionSnapshot, now: Date) -> Bool {
        guard snapshot.confidence >= 0.25 else { return false }
        let signature = [
            snapshot.facePresent ? "face" : "no_face",
            snapshot.attentionZone.rawValue,
            snapshot.eyeVisibility == "closed" ? "eyes_closed" : "eyes_open",
            snapshot.facePosition.rawValue
        ].joined(separator: "|")
        defer {
            lastCameraPersistedSignature = signature
            lastCameraPersistedAt = now
        }
        if signature != lastCameraPersistedSignature { return true }
        return lastCameraPersistedAt.map { now.timeIntervalSince($0) >= 30 } ?? true
    }

    private func recordCameraHealth(_ snapshot: AttentionSnapshot, now: Date) {
        cameraHealthSamples.append((now, snapshot.facePresent, snapshot.confidence))
        cameraHealthSamples = cameraHealthSamples.filter { now.timeIntervalSince($0.timestamp) <= 5 * 60 }
        guard lastCameraHealthAt.map({ now.timeIntervalSince($0) >= 5 * 60 }) ?? true else { return }
        lastCameraHealthAt = now
        let samples = cameraHealthSamples
        let faceFrames = samples.filter(\.facePresent).count
        let meanConfidence = samples.map(\.confidence).reduce(0, +) / Double(max(samples.count, 1))
        append(
            .init(
                type: .sensorHealth,
                confidence: 1,
                payload: [
                    "sensor": "camera",
                    "sample_count": "\(samples.count)",
                    "face_frame_ratio": String(format: "%.3f", Double(faceFrames) / Double(max(samples.count, 1))),
                    "mean_confidence": String(format: "%.3f", meanConfidence),
                    "health_interval_seconds": "300"
                ],
                workspaceTopologyVersion: environment.topology.version
            )
        )
    }

    private func recordVisualObjectEvidenceIfNeeded(_ snapshot: AttentionSnapshot, now: Date = Date()) {
        guard environment.settings.contextFabric.objectGestureLayerEnabled else {
            return
        }
        let builder = ObjectPresenceBuilder()
        for observation in snapshot.visualObjects {
            guard let objectClass = builder.normalizedClass(from: observation.label), observation.confidence >= 0.45 else {
                continue
            }
            let lastEventAt = lastVisualObjectEventAt[objectClass] ?? .distantPast
            guard now.timeIntervalSince(lastEventAt) >= environment.settings.contextFabric.objectPresenceMinimumIntervalSeconds else {
                continue
            }
            guard let payload = builder.payload(
                objectClass: objectClass,
                inHand: false,
                durationSeconds: 0,
                confidence: observation.confidence
            ) else {
                continue
            }
            lastVisualObjectEventAt[objectClass] = now
            append(
                .init(
                    type: .objectPresence,
                    confidence: observation.confidence,
                    payload: payload,
                    workspaceTopologyVersion: environment.topology.version
                )
            )
        }
    }

    private func handleSensorEvent(_ sensorEvent: SensorEvent) {
        guard scheduleGate.status().sensorAllowed else {
            return
        }
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
            guard isPresenceActive() else {
                currentFocus = focus
                currentFocusStartedAt = nil
                return
            }
            let previousAppName = currentFocus?.appName
            focusChangeTimestamps.append(Date())
            focusChangeTimestamps = focusChangeTimestamps.suffix(20)
            closeCurrentFocusInterval(reason: "focus_changed")
            currentFocus = focus
            currentFocusStartedAt = Date()
            setLatestContextLine(nil)
            let appFocusEvent = ObserverEvent(
                type: .appFocus,
                displayRole: focus.displayRole,
                appID: focus.appID,
                confidence: focus.windowTitle == nil ? 0.75 : 0.95,
                payload: focus.eventPayload,
                workspaceTopologyVersion: environment.topology.version
            )
            append(appFocusEvent)
            recordAttentionSpanIfNeeded(currentFocusEvent: appFocusEvent)
            append(
                .init(
                    type: .breakpoint,
                    displayRole: focus.displayRole,
                    appID: focus.appID,
                    confidence: 0.8,
                    payload: BreakpointBuilder().mediumFocusChange(
                        previousAppName: previousAppName,
                        nextFocus: focus
                    ),
                    workspaceTopologyVersion: environment.topology.version
                )
            )
            notifyStateChanged()

        case .inputActivity(let activity):
            latestInputActivity = activity
            updatePresence(facePresent: false, input: activity, now: Date())
            guard isPresenceActive() else {
                notifyStateChanged()
                return
            }
            append(
                .init(
                    type: .inputActivity,
                    confidence: 0.8,
                    payload: activity.eventPayload,
                    workspaceTopologyVersion: environment.topology.version
                )
            )
            updateFineInputPauseBreakpoint(activity)
            updateIdleBoundary(activity)
            recordGazeCalibrationSampleIfNeeded()
            captureOCRWritingFallbackIfNeeded(activity)
            releaseSecurityIncidentsIfOwnerReturned(input: activity)
            commitPendingAwayPresenceIncidentIfNeeded()
            pauseMediaIfUserAppearsAway()
            resumeMediaIfUserReturned()
            notifyStateChanged()

        case .screenContext(let context):
            guard isPresenceActive() else { return }
            recordContentContext(
                context,
                legacyType: .screenContext,
                contextKind: "screen",
                displayPrefix: "Контекст"
            )
            captureReadingOCRIfNeeded(context)

        case .writingContext(let context):
            guard isPresenceActive() else { return }
            lastWritingContextAt = Date()
            recordContentContext(
                context,
                legacyType: .writingContext,
                contextKind: "active_writing",
                displayPrefix: "Пишет"
            )
            recordTextAffectCueIfNeeded(
                text: context.focusedElementValue ?? context.selectedText,
                appName: context.appName
            )
        }
        recordCognitiveStateOnCadence()
    }

    /// State evaluation decodes a non-trivial history window. Keeping it on a
    /// cadence prevents input and camera traffic from blocking the menu-bar UI.
    private func recordCognitiveStateOnCadence(now: Date = Date()) {
        guard lastCognitiveEvaluationAt.map({ now.timeIntervalSince($0) >= 30 }) ?? true else {
            return
        }
        lastCognitiveEvaluationAt = now
        recordCognitiveStateIfNeeded(now: now)
    }

    private func recordCognitiveStateIfNeeded(now: Date = Date()) {
        guard mode == .observing else {
            return
        }
        let events = (try? environment.eventStore.recentEvents(limit: 260)) ?? []
        guard let decision = CognitiveStateEvaluator(
            settings: environment.settings.cognitiveSettings
        ).evaluate(events: events, now: now) else {
            return
        }
        guard decision.state != latestCognitiveState else {
            return
        }

        var payload = decision.payload
        if let latestCognitiveStateStartedAt {
            payload["previous_duration_seconds"] = String(format: "%.1f", now.timeIntervalSince(latestCognitiveStateStartedAt))
        }
        if let latestCognitiveState, latestCognitiveState == "flow" {
            payload["flow_exit_reason"] = decision.state == "engaged" ? "natural_end" : "degradation"
            payload["breakpoint_trigger"] = "true"
        }

        latestCognitiveState = decision.state
        latestCognitiveStateStartedAt = now
        append(
            .init(
                type: .cognitiveState,
                confidence: decision.confidence,
                payload: payload,
                workspaceTopologyVersion: environment.topology.version
            )
        )

        if payload["breakpoint_trigger"] == "true" {
            append(
                .init(
                    type: .breakpoint,
                    confidence: decision.confidence,
                    payload: [
                        "level": "coarse",
                        "reason": "flow_exit",
                        "state": decision.state,
                        "truncated_by_schedule": "false"
                    ],
                    workspaceTopologyVersion: environment.topology.version
                )
            )
            closeCurrentEpisode(outcome: "flow_exit", now: now)
        }
    }

    private func recordContentContext(
        _ context: ScreenContextSnapshot,
        legacyType: ObserverEventType,
        contextKind: String,
        displayPrefix: String
    ) {
        guard isPresenceActive() else {
            return
        }
        recentMediaPageTracker.observe(
            resourceURL: context.resourceURL,
            appName: context.appName,
            windowTitle: context.windowTitle
        )
        let allowRawKinds = Set(environment.settings.rawContextStorageKinds)
        guard let annotation = ContentContextAnnotator().annotate(
            context: context,
            allowRawKinds: allowRawKinds
        ) else {
            return
        }

        var payload = annotation.payload
        payload["app_name"] = context.appName
        payload["context_kind"] = contextKind
        payload["content_source"] = "accessibility"
        if let appID = context.appID {
            payload["app_id"] = appID
        }
        if let displayRole = context.displayRole {
            payload["display_role"] = displayRole.rawValue
        }
        if let screenIndex = context.screenIndex {
            payload["screen_index"] = "\(screenIndex)"
        }
        if let resourceURL = context.resourceURL {
            // The reader removes credentials and secret query parameters before
            // this point. URLs remain local and are excluded from cloud prompts.
            payload["resource_url"] = resourceURL
            payload["resource_domain"] = URL(string: resourceURL)?.host ?? ""
        }
        if let entityName = annotation.sourceEntityDisplayName,
           let entity = try? environment.entityStore.upsertEntity(
            kind: annotation.contentKind == "email" ? "person" : "channel",
            displayName: entityName
        ) {
            payload["source_entity_id"] = entity.id
            payload.removeValue(forKey: "source_entity_display_name")
            try? environment.entityStore.recordInteraction(
                entityID: entity.id,
                sentiment: annotation.sentiment,
                reaction: nil
            )
        }

        let contentEvent = ObserverEvent(
            type: .contentContext,
            displayRole: context.displayRole,
            appID: context.appID,
            confidence: context.confidence,
            payload: payload,
            workspaceTopologyVersion: environment.topology.version
        )
        append(contentEvent)
        if annotation.contentKind == "prompt",
           let anchor = IntentionAttributionBuilder().anchorPayload(for: contentEvent) {
            append(
                .init(
                    type: .intentionAnchor,
                    confidence: 0.88,
                    payload: anchor,
                    workspaceTopologyVersion: environment.topology.version
                )
            )
        }

        guard !environment.settings.fullContextMode else {
            return
        }

        var legacyPayload = context.eventPayload
        legacyPayload["context_kind"] = contextKind
        append(
            .init(
                type: legacyType,
                displayRole: context.displayRole,
                appID: context.appID,
                confidence: context.confidence,
                payload: legacyPayload,
                workspaceTopologyVersion: environment.topology.version
            )
        )
    }

    private func widgetContextLine(
        prefix: String,
        annotation: ContentContextAnnotation,
        context: ScreenContextSnapshot
    ) -> String? {
        switch environment.settings.pillVerbosity {
        case "full":
            return context.shortDisplayLine(prefix: prefix)
        case "status_only":
            return nil
        default:
            return semanticWidgetContextLine(prefix: prefix, annotation: annotation, context: context)
        }
    }

    private func semanticWidgetContextLine(
        prefix: String,
        annotation: ContentContextAnnotation,
        context: ScreenContextSnapshot
    ) -> String? {
        let topic = cleanInsightFragment(annotation.topic, allowShortCodeLikeText: false)
        let entity = cleanInsightFragment(annotation.sourceEntityDisplayName, allowShortCodeLikeText: false)
        let app = cleanInsightFragment(context.appName)
        let compactTopic = topic.map { ": \($0)" } ?? ""

        switch annotation.contentKind {
        case "prompt":
            guard topic != nil else {
                return nil
            }
            let action = context.hasTextualFocus ? "формулирует задачу" : "читает ответ"
            return "Диалог с ИИ: \(action)\(compactTopic)"
        case "message", "email":
            guard topic != nil || entity != nil else {
                return nil
            }
            let channel = annotation.contentKind == "email" ? "Почта" : "Сообщения"
            let action = annotation.isIncoming ? "читает" : "пишет"
            if let entity {
                return "\(channel): \(action) \(entity)\(compactTopic)"
            }
            return "\(channel): \(action)\(compactTopic)"
        case "code":
            guard topic != nil else {
                return nil
            }
            return "Код: работает с фрагментом\(compactTopic)"
        case "doc":
            guard topic != nil else {
                return nil
            }
            return "Документ: редактирует смысл\(compactTopic)"
        case "video":
            guard topic != nil else {
                return nil
            }
            return "Видео: смотрит контент\(compactTopic)"
        case "article":
            guard let topic else {
                return nil
            }
            if looksSearchLike(topic) || looksSearchLike(context.windowTitle ?? "") {
                return "Веб: ищет по теме: \(topic)"
            }
            return "Веб: читает страницу\(compactTopic)"
        default:
            break
        }

        let kind = readableContentKind(annotation.contentKind)
        let subject: String
        if let entity, ["message", "email"].contains(annotation.contentKind) {
            subject = "\(kind) с \(entity)"
        } else if let app {
            subject = "\(app): \(kind)"
        } else {
            subject = kind
        }
        if let topic, !topic.isEmpty, topic.caseInsensitiveCompare(subject) != .orderedSame {
            return "\(prefix): \(subject) · \(topic)"
        }
        return "\(prefix): \(subject)"
    }

    private func looksSearchLike(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("search")
            || lower.contains("google")
            || lower.contains("results")
            || lower.contains("поиск")
            || lower.contains("найти")
    }

    private func captureOCRWritingFallbackIfNeeded(_ activity: InputActivitySnapshot) {
        guard activity.secondsSinceKeyboard <= 8 else {
            return
        }
        guard let currentFocus, let appID = currentFocus.appID else {
            return
        }
        let contentEnabled = environment.settings.fullContextMode
            ? !environment.privacyStore.isExcluded(appID)
            : environment.privacyStore.isContentAllowed(appID)
        guard contentEnabled else {
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
            recordTextAffectCueIfNeeded(text: result.text, appName: result.appName)
            let context = ScreenContextSnapshot(
                appID: result.appID,
                appName: result.appName,
                windowTitle: result.windowTitle,
                windowRole: nil,
                document: nil,
                focusedElementRole: nil,
                focusedElementTitle: nil,
                focusedElementValue: result.text,
                selectedText: nil,
                resourceURL: nil,
                screenIndex: currentFocus.screenIndex,
                displayRole: currentFocus.displayRole,
                confidence: min(result.confidence, 0.55)
            )
            recordContentContext(
                context,
                legacyType: .ocrContext,
                contextKind: "writing_fallback",
                displayPrefix: "Контекст"
            )
            guard !environment.settings.fullContextMode else {
                return
            }
            var payload = result.eventPayload
            payload["context_kind"] = "writing_fallback"
            payload["fallback_reason"] = "accessibility_text_unavailable"
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

    private func captureReadingOCRIfNeeded(_ context: ScreenContextSnapshot, now: Date = Date()) {
        guard mode == .observing, environment.settings.fullContextMode else {
            return
        }
        guard let currentFocus, let appID = currentFocus.appID,
              !environment.privacyStore.isExcluded(appID) else {
            return
        }
        guard lastReadingOCRAt.map({ now.timeIntervalSince($0) >= 40 }) ?? true else {
            return
        }

        do {
            guard let result = try ScreenOCRService().recognizeText(for: currentFocus) else {
                lastReadingOCRAt = now
                return
            }
            let key = [result.appID ?? "", result.text].joined(separator: "|")
            guard key != lastReadingOCRKey else {
                lastReadingOCRAt = now
                return
            }

            lastReadingOCRAt = now
            lastReadingOCRKey = key
            let ocrContext = ScreenContextSnapshot(
                appID: result.appID,
                appName: result.appName,
                windowTitle: result.windowTitle ?? context.windowTitle,
                windowRole: nil,
                document: context.document,
                focusedElementRole: nil,
                focusedElementTitle: nil,
                focusedElementValue: result.text,
                selectedText: nil,
                resourceURL: context.resourceURL,
                screenIndex: currentFocus.screenIndex,
                displayRole: currentFocus.displayRole,
                confidence: min(result.confidence, 0.7)
            )
            recordContentContext(
                ocrContext,
                legacyType: .ocrContext,
                contextKind: "periodic_reading_ocr",
                displayPrefix: "Контекст"
            )
        } catch {
            lastReadingOCRAt = now
        }
    }

    private func recordTextAffectCueIfNeeded(text: String?, appName: String?) {
        guard let text else {
            return
        }
        guard let cue = TextAffectCueBuilder().build(
            text: text,
            appName: appName,
            activityInsight: nil
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
        appendBehaviorCueForFusion(
            confidence: cue.confidence,
            payload: cue.payload,
            displayText: cue.insight,
            displayEligible: true,
            surfaceAsContext: true,
            now: now
        )
    }

    private func notifyStateChanged() {
        onStateChanged?(stateSnapshot)
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
            activityInsight: nil,
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
        let displayEligible = cue.payload["display_eligible"] != "false"
        appendBehaviorCueForFusion(
            confidence: cue.confidence,
            payload: cue.payload,
            displayText: cue.insight,
            displayEligible: displayEligible && cue.name != "steady_focus",
            surfaceAsContext: false,
            now: now
        )
    }

    private func recordGazeCalibrationSampleIfNeeded(now: Date = Date()) {
        guard mode == .observing else {
            return
        }

        guard let sample = GazeCalibrationBuilder().build(
            attention: smoothedAttentionForDisplay,
            input: latestInputActivity,
            currentFocus: currentFocus,
            activityInsight: nil
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
        confirmedAwayBeforeCurrent: Bool,
        now: Date = Date()
    ) {
        guard mode == .observing else {
            return
        }
        guard let incident = AwayPresenceIncidentBuilder().build(
            currentAttention: currentAttention,
            missingFaceSamplesBeforeCurrent: missingFaceSamplesBeforeCurrent,
            confirmedAwayBeforeCurrent: confirmedAwayBeforeCurrent,
            input: latestInputActivity,
            currentFocus: currentFocus,
            activityInsight: nil
        ) else {
            return
        }

        if ownerFaceRecognizer.isOwnerFace(currentAttention.jpegData) == true {
            append(
                .init(
                    type: .awayPresenceIncident,
                    displayRole: currentFocus?.displayRole,
                    appID: currentFocus?.appID,
                    confidence: 0.72,
                    payload: incident.payload.merging([
                        "owner_identity": "recognized_owner",
                        "review_state": "dismissed_owner_face_match",
                        "media_written": "false"
                    ]) { current, _ in current },
                    workspaceTopologyVersion: environment.topology.version
                )
            )
            return
        }

        let enoughTimePassed = lastAwayPresenceIncidentAt.map { now.timeIntervalSince($0) >= 600 } ?? true
        guard enoughTimePassed else {
            return
        }

        lastAwayPresenceIncidentAt = now
        pendingAwayPresenceIncident = PendingAwayPresenceIncident(
            firstSeenAt: now,
            payload: incident.payload,
            jpegData: currentAttention.jpegData,
            displayRole: currentFocus?.displayRole,
            appID: currentFocus?.appID,
            confidence: incident.confidence
        )
        append(
            .init(
                type: .awayPresenceIncident,
                displayRole: currentFocus?.displayRole,
                appID: currentFocus?.appID,
                confidence: incident.confidence,
                payload: incident.payload.merging([
                    "review_state": "pending_owner_return_gate",
                    "media_written": "false"
                ]) { current, _ in current },
                workspaceTopologyVersion: environment.topology.version
            )
        )
        notifyStateChanged()
    }

    private func commitPendingAwayPresenceIncidentIfNeeded(now: Date = Date()) {
        guard let pending = pendingAwayPresenceIncident else {
            return
        }

        if ownerFaceRecognizer.isOwnerFace(pending.jpegData) == true {
            pendingAwayPresenceIncident = nil
            append(
                .init(
                    type: .awayPresenceIncident,
                    displayRole: pending.displayRole,
                    appID: pending.appID,
                    confidence: min(pending.confidence, 0.45),
                    payload: pending.payload.merging([
                        "owner_identity": "recognized_owner",
                        "review_state": "dismissed_owner_face_match",
                        "media_written": "false"
                    ]) { current, _ in current },
                    workspaceTopologyVersion: environment.topology.version
                )
            )
            return
        }

        let ownerHasReturned = smoothedAttentionForDisplay?.facePresent == true
            && (latestInputActivity?.secondsSinceAnyInput ?? .greatestFiniteMagnitude) <= 5
        guard now.timeIntervalSince(pending.firstSeenAt) >= 8 || ownerHasReturned else {
            return
        }

        pendingAwayPresenceIncident = nil
        var payload = pending.payload
        if let storedIncident = try? environment.securityIncidentStore.record(
            payload: payload,
            jpegData: pending.jpegData
        ) {
            payload["security_incident_id"] = storedIncident.id.uuidString
            payload["security_summary"] = storedIncident.summary
            payload["photo_path"] = storedIncident.photoURL?.path
            payload["screenshot_path"] = storedIncident.screenshotURL?.path
            payload["transcript_path"] = storedIncident.transcriptURL?.path
            payload["transcript_status"] = "placeholder"
            payload["audio_status"] = "not_recorded"
        }
        payload["review_state"] = "committed_waiting_owner_review"
        payload["media_written"] = "true"
        append(
            .init(
                type: .securityIncident,
                displayRole: pending.displayRole,
                appID: pending.appID,
                confidence: pending.confidence,
                payload: payload,
                workspaceTopologyVersion: environment.topology.version
            )
        )
    }

    private func releaseSecurityIncidentsIfOwnerReturned(
        input: InputActivitySnapshot? = nil,
        now: Date = Date()
    ) {
        guard smoothedAttentionForDisplay?.facePresent == true else {
            return
        }

        let activity = input ?? latestInputActivity
        guard (activity?.secondsSinceAnyInput ?? .greatestFiniteMagnitude) <= 5 else {
            return
        }

        if pendingAwayPresenceIncident != nil {
            commitPendingAwayPresenceIncidentIfNeeded(now: now)
        }

        let released = environment.securityIncidentStore.releasePendingForReview()
        guard released > 0 else {
            return
        }

        setLatestContextLine(
            released == 1
                ? "Защита: 1 событие во время отсутствия"
                : "Защита: \(released) события во время отсутствия",
            now: now
        )
        notifyStateChanged()
    }

    private func updateOwnerFaceProfileIfNeeded(_ attention: AttentionSnapshot) {
        guard attention.facePresent, attention.faceCount == 1 else {
            return
        }
        guard (latestInputActivity?.secondsSinceAnyInput ?? .greatestFiniteMagnitude) <= 10 else {
            return
        }
        ownerFaceRecognizer.learnOwnerFace(from: attention.jpegData)
    }

    private func recordSmileCueIfNeeded(_ attention: AttentionSnapshot, now: Date = Date()) {
        guard mode == .observing else {
            return
        }
        guard attention.smileCandidate == true else {
            return
        }
        guard let safety = cameraCueSafety(for: attention, cue: "positive_reaction_candidate", now: now) else {
            return
        }
        lastSmileCueAt = now

        var payload: [String: String] = [
            "cue": "positive_reaction_candidate",
            "interpretation": currentFocus?.isCommunicationContext == true
                ? "smile_in_communication_context"
                : "smile_in_current_context",
            "detector_tier": "tier1",
            "cascade_stage": "tier1_candidate",
            "tier2_required_for_publication": "true",
            "temporal_model_required": "true",
            "display_eligible": "false",
            "quality_gate": "passed",
            "refractory_seconds": String(format: "%.0f", environment.settings.cameraDetectorSettings.cueRefractorySeconds),
            "hourly_budget": "\(environment.settings.cameraDetectorSettings.cueHourlyBudget)",
            "self_throttled": safety.selfThrottled ? "true" : "false"
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
        if let latestContent = ((try? environment.eventStore.recentEvents(limit: 40)) ?? [])
            .reversed()
            .first(where: { event in
                event.type == .contentContext
                    && now.timeIntervalSince(event.timestamp) <= 45
                    && ["message", "email"].contains(event.payload["content_kind"])
            }) {
            payload["content_kind"] = latestContent.payload["content_kind"] ?? "message"
            payload["content_topic"] = latestContent.payload["topic"]
            payload["content_sentiment"] = latestContent.payload["sentiment"]
            if payload["interpretation"] == "smile_in_current_context" {
                payload["interpretation"] = "smile_in_communication_context"
            }
        }

        let isCommunicationSmile = payload["interpretation"] == "smile_in_communication_context"

        appendBehaviorCueForFusion(
            displayRole: currentFocus?.displayRole,
            appID: currentFocus?.appID,
            confidence: 0.36 * safety.confidenceMultiplier,
            payload: payload,
            displayText: isCommunicationSmile
                ? "Камера: кандидат улыбки в переписке"
                : "Камера: кандидат улыбки",
            displayEligible: false,
            surfaceAsContext: false,
            now: now
        )
        notifyStateChanged()
    }

    private func recordYawnCueIfNeeded(_ attention: AttentionSnapshot, now: Date = Date()) {
        guard mode == .observing else {
            return
        }
        guard attention.yawnCandidate == true else {
            mouthOpenCandidateStartedAt = nil
            return
        }

        if mouthOpenCandidateStartedAt == nil {
            mouthOpenCandidateStartedAt = now
            return
        }

        guard now.timeIntervalSince(mouthOpenCandidateStartedAt ?? now) >= 2.0 else {
            return
        }

        guard let safety = cameraCueSafety(for: attention, cue: "energy_drop_candidate", now: now) else {
            return
        }
        lastYawnCueAt = now

        var payload: [String: String] = [
            "cue": "energy_drop_candidate",
            "interpretation": "yawn_detected",
            "detector_tier": "tier1",
            "cascade_stage": "tier1_candidate",
            "tier2_required_for_publication": "true",
            "temporal_model_required": "true",
            "display_eligible": "false",
            "quality_gate": "passed",
            "refractory_seconds": String(format: "%.0f", environment.settings.cameraDetectorSettings.cueRefractorySeconds),
            "hourly_budget": "\(environment.settings.cameraDetectorSettings.cueHourlyBudget)",
            "self_throttled": safety.selfThrottled ? "true" : "false"
        ]
        if let score = attention.mouthOpenScore {
            payload["mouth_open_score"] = String(format: "%.3f", score)
        }
        if let source = attention.mouthSignalSource {
            payload["mouth_signal_source"] = source
        }
        if let currentFocus {
            payload["app_name"] = currentFocus.appName
            if let appID = currentFocus.appID {
                payload["app_id"] = appID
            }
        }
        appendBehaviorCueForFusion(
            displayRole: currentFocus?.displayRole,
            appID: currentFocus?.appID,
            confidence: 0.34 * safety.confidenceMultiplier,
            payload: payload,
            displayText: "Камера: кандидат зевка",
            displayEligible: false,
            surfaceAsContext: false,
            now: now
        )
        notifyStateChanged()
    }

    private func cameraCueSafety(
        for attention: AttentionSnapshot,
        cue: String,
        now: Date
    ) -> (confidenceMultiplier: Double, selfThrottled: Bool)? {
        let settings = environment.settings.cameraDetectorSettings
        let qualitySettings = CameraCueQualityGate.Settings(
            minimumFaceArea: settings.minimumEmotionFaceArea,
            minimumBrightness: settings.minimumEmotionFrameBrightness,
            maximumBrightness: settings.maximumEmotionFrameBrightness,
            minimumSharpness: settings.minimumEmotionFrameSharpness
        )
        guard CameraCueQualityGate().rejection(
            facePresent: attention.facePresent,
            faceArea: attention.faceArea,
            brightness: attention.frameBrightness,
            sharpness: attention.frameSharpness,
            settings: qualitySettings
        ) == nil else {
            return nil
        }

        switch cameraCueRateLimiter.decide(
            cue: cue,
            now: now,
            refractorySeconds: settings.cueRefractorySeconds,
            hourlyBudget: settings.cueHourlyBudget,
            throttledConfidenceMultiplier: settings.throttledCueConfidenceMultiplier
        ) {
        case .suppressedByRefractory:
            return nil
        case let .emit(confidenceMultiplier, selfThrottled):
            return (confidenceMultiplier, selfThrottled)
        }
    }

    private func appendBehaviorCueForFusion(
        displayRole: WorkspaceTopology.DisplayRole? = nil,
        appID: String? = nil,
        confidence: Double,
        payload: [String: String],
        displayText: String,
        displayEligible: Bool,
        surfaceAsContext: Bool,
        now: Date
    ) {
        let event = ObserverEvent(
            type: .behaviorCue,
            displayRole: displayRole,
            appID: appID,
            confidence: confidence,
            payload: payload,
            workspaceTopologyVersion: environment.topology.version
        )
        append(event)

        let recentEvents = (try? environment.eventStore.recentEvents(limit: 160)) ?? []
        let decision = FusionEngine().decide(candidate: event, recentEvents: recentEvents)
        append(
            .init(
                type: .fusionHypothesis,
                displayRole: displayRole,
                appID: appID,
                confidence: decision.confidence,
                payload: decision.payload,
                workspaceTopologyVersion: environment.topology.version
            )
        )
        recordBoundReactionIfNeeded(cueEvent: event)

        guard displayEligible, decision.surfaceAllowed else {
            return
        }
        guard !proactiveHintsBlocked() else {
            return
        }

        let resolvedDisplayText = fusionDisplayText(
            defaultText: displayText,
            fusion: decision,
            candidatePayload: payload
        )
        if surfaceAsContext {
            setLatestContextLine(resolvedDisplayText, now: now)
        } else {
            latestHint = resolvedDisplayText
            lastHintAt = now
        }
    }

    private func fusionDisplayText(
        defaultText: String,
        fusion: FusionDecision,
        candidatePayload: [String: String]
    ) -> String {
        guard candidatePayload["cue"] == "frustration_candidate",
              fusion.payload["causal_attribution"] == "fresh_communication_context",
              let topic = usableSemanticTopic(fusion.payload["causal_context_topic"])
        else {
            return defaultText
        }
        return "Фрикция: реакция совпала с перепиской · \(topic)"
    }

    private func proactiveHintsBlocked() -> Bool {
        guard let latestCognitiveState else {
            return false
        }
        return environment.settings.cognitiveSettings.proactiveBlockedStates.contains(latestCognitiveState)
    }

    private func recordBoundReactionIfNeeded(cueEvent: ObserverEvent) {
        let recentEvents = (try? environment.eventStore.recentEvents(limit: 80)) ?? []
        guard let payload = BoundReactionBuilder().build(
            cueEvent: cueEvent,
            recentEvents: recentEvents
        ) else {
            return
        }

        if let entityID = payload["entity_id"] {
            try? environment.entityStore.recordInteraction(
                entityID: entityID,
                sentiment: payload["sentiment"] ?? "neutral",
                reaction: payload["cue"]
            )
        }

        append(
            .init(
                type: .boundReaction,
                displayRole: cueEvent.displayRole,
                appID: cueEvent.appID,
                confidence: min(
                    Double(payload["confidence_cap"] ?? "") ?? 0.9,
                    min(0.9, cueEvent.confidence + 0.2)
                ),
                payload: payload,
                workspaceTopologyVersion: environment.topology.version
            )
        )
    }

    private func enterOffHours() {
        if mode == .observing {
            closeObservationInterval(reason: "off_hours")
        }
        mode = .offHours
        sessionStartedAt = nil
        currentSessionID = nil
        currentEpisodeID = nil
        sensor?.stop()
        stopSummaryTimer()
        stopGeminiInsightTimer()
        stopMediaTimer()
        stopPredictionTimer()
        if cameraAttentionService.isActive {
            cameraAttentionService.stop()
        }
        latestCameraStatus = nil
        setLatestContextLine(nil)
        notifyStateChanged()
    }

    private func closeForScheduleEnd(now: Date) {
        let summary = generateLocalSummary()
        _ = summary
        requestDailyGeminiInsightIfNeeded(now: now)
        closeCurrentEpisode(outcome: "schedule_end", now: now)
        closeCurrentFocusInterval(reason: "schedule_end")
        closeObservationInterval(reason: "schedule_end", now: now)
        append(
            .init(
                type: .sessionBoundary,
                confidence: 0.9,
                payload: [
                    "boundary": "schedule_end",
                    "reason": "work_schedule",
                    "truncated_by_schedule": "true"
                ],
                workspaceTopologyVersion: environment.topology.version
            )
        )
        enterOffHours()
    }

    private func requestDailyGeminiInsightIfNeeded(now: Date = Date()) {
        guard environment.settings.geminiEnabled else {
            return
        }
        let calendar = Calendar.current
        guard !((try? environment.eventStore.recentEvents(limit: 800)) ?? []).contains(where: { event in
            calendar.isDate(event.timestamp, inSameDayAs: now)
                && event.payload["request_kind"] == "daily_patterns"
                && event.payload["status"] != "skipped_missing_key"
        }) else {
            return
        }
        requestGeminiInsight(
            requestKind: "daily_patterns",
            widgetMode: false,
            copyToPasteboard: false
        )
    }

    private func closeObservationInterval(reason: String, now: Date = Date()) {
        guard let start = currentObservationIntervalStartedAt else {
            return
        }
        let gate = scheduleGate
        try? environment.observationCalendarStore.recordInterval(
            start: start,
            end: now,
            plannedStart: gate.workStart(on: start),
            plannedEnd: gate.workEnd(on: start),
            outsideDefaultSchedule: currentObservationOutsideDefaultSchedule,
            offReason: reason == "schedule_end" ? "none" : reason
        )
        currentObservationIntervalStartedAt = nil
        currentObservationOutsideDefaultSchedule = false
    }

    private func applyMorningTailIfNeeded(now: Date) {
        let gate = scheduleGate
        guard let start = gate.workStart(on: now),
              now.timeIntervalSince(start) <= environment.settings.workSchedule.morningTailMinutes * 60
        else {
            return
        }
        let events = (try? environment.eventStore.recentEvents(limit: 400)) ?? []
        guard let previousContext = events.reversed().first(where: { event in
            event.timestamp < start && event.type == .contentContext
        }) else {
            return
        }
        let days = max(1, Calendar.current.dateComponents([.day], from: previousContext.timestamp, to: now).day ?? 1)
        let label = days >= 2 ? "последняя сессия: \(days)д назад" : "вчера"
        let topic = previousContext.payload["topic"]
            ?? previousContext.payload["app_name"]
            ?? "контекст не найден"
        setLatestContextLine("\(label): \(topic)", now: now)
        if days > 1 {
            append(
                .init(
                    type: .observationGap,
                    confidence: 0.8,
                    payload: [
                        "duration_days": "\(days)",
                        "reason": "non_observed_calendar_gap",
                        "post_gap_resume": "true",
                        "previous_event_id": previousContext.id.uuidString
                    ],
                    workspaceTopologyVersion: environment.topology.version
                )
            )
        }
    }

    private func closeCurrentFocusInterval(reason: String) {
        guard let currentFocus, let currentFocusStartedAt else {
            return
        }

        let duration = Date().timeIntervalSince(currentFocusStartedAt)
        guard duration >= 1 else {
            return
        }

        guard duration <= 18 * 60 * 60 else {
            append(
                .init(
                    type: .focusIntervalRejected,
                    confidence: 1,
                    payload: [
                        "reason": "duration_over_18h",
                        "duration_seconds": String(format: "%.1f", duration),
                        "app_name": currentFocus.appName
                    ],
                    workspaceTopologyVersion: environment.topology.version
                )
            )
            self.currentFocusStartedAt = Date()
            return
        }

        var payload: [String: String] = [
            "app_name": currentFocus.appName,
            "duration_seconds": String(format: "%.1f", duration),
            "reason": reason
        ]
        if scheduleGate.isTruncatedBySchedule(start: currentFocusStartedAt, end: Date()) || reason == "schedule_end" {
            payload["truncated_by_schedule"] = "true"
        }
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
            closeCurrentEpisode(outcome: "idle_started")
            let breakpointPayload = BreakpointBuilder().coarseIdleStart(
                secondsSinceAnyInput: activity.secondsSinceAnyInput
            )
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
            append(
                .init(
                    type: .breakpoint,
                    confidence: 0.82,
                    payload: breakpointPayload,
                    workspaceTopologyVersion: environment.topology.version
                )
            )
            _ = generateLocalSummary()
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

    private func updateFineInputPauseBreakpoint(_ activity: InputActivitySnapshot) {
        if activity.secondsSinceAnyInput < 10 {
            isFineInputPauseOpen = false
            return
        }

        guard !isFineInputPauseOpen,
              let payload = BreakpointBuilder().fineInputPause(
                secondsSinceAnyInput: activity.secondsSinceAnyInput
              )
        else {
            return
        }

        isFineInputPauseOpen = true
        append(
            .init(
                type: .breakpoint,
                confidence: 0.7,
                payload: payload,
                workspaceTopologyVersion: environment.topology.version
            )
        )
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

    private func startStabilityTimers() {
        stopStabilityTimers()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.mode == .observing else { return }
                self.append(
                    .init(
                        type: .heartbeat,
                        confidence: 1,
                        payload: ["mode": "observing", "sensor_active": "true"],
                        workspaceTopologyVersion: self.environment.topology.version
                    )
                )
            }
        }
        focusFlushTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.mode == .observing, self.currentFocus != nil else { return }
                self.closeCurrentFocusInterval(reason: "periodic_flush")
                self.currentFocusStartedAt = Date()
            }
        }
    }

    private func stopStabilityTimers() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        focusFlushTimer?.invalidate()
        focusFlushTimer = nil
    }

    private func startGeminiInsightTimer() {
        stopGeminiInsightTimer()
        guard environment.settings.geminiEnabled, environment.settings.geminiAutoInsightEnabled else {
            return
        }
        let interval = ProcessInfo.processInfo.environment["OBSERVER_GEMINI_WIDGET_INTERVAL_SECONDS"]
            .flatMap(TimeInterval.init) ?? environment.settings.geminiAutoInsightIntervalSeconds
        guard interval > 0 else {
            return
        }

        geminiInsightTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.mode == .observing else {
                    return
                }
                self.requestGeminiInsight(
                    requestKind: "widget_sensemaking",
                    widgetMode: true,
                    copyToPasteboard: false
                )
            }
        }

        Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.mode == .observing else {
                    return
                }
                guard self.latestExternalWidgetInsightLine() == nil else {
                    return
                }
                self.requestGeminiInsight(
                    requestKind: "widget_sensemaking",
                    widgetMode: true,
                    copyToPasteboard: false
                )
            }
        }
    }

    private func stopGeminiInsightTimer() {
        geminiInsightTimer?.invalidate()
        geminiInsightTimer = nil
    }

    private func recordGeminiKeyStatusIfChanged() {
        let configured = GeminiKeyStore(directory: environment.dataDirectory).hasKey()
        guard lastGeminiKeyAvailability != configured else { return }
        lastGeminiKeyAvailability = configured
        append(
            .init(
                type: .externalLLMRequest,
                confidence: 1,
                payload: [
                    "provider": "gemini",
                    "status": configured ? "key_ready" : "key_missing",
                    "status_change": "true",
                    "storage": "local_private_file"
                ],
                workspaceTopologyVersion: environment.topology.version
            )
        )
        if !configured {
            latestHint = "Внешний анализ выключен: нет ключа"
            lastHintAt = Date()
        }
    }

    private func startPredictionTimer() {
        stopPredictionTimer()
        guard scheduleGate.predictionAllowed() else {
            return
        }
        let interval = environment.settings.cognitiveSettings.predictionIntervalSeconds
        predictionTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordPredictionIfAllowed()
            }
        }
    }

    private func stopPredictionTimer() {
        predictionTimer?.invalidate()
        predictionTimer = nil
    }

    private func recordPredictionIfAllowed() {
        guard mode == .observing, scheduleGate.predictionAllowed() else {
            return
        }
        let events = (try? environment.eventStore.recentEvents(limit: 220)) ?? []
        let readiness = ReadinessReportBuilder(
            settings: environment.settings.readinessSettings
        ).readinessReport(events: events)
        guard readiness.isReadyForPrediction else {
            append(
                .init(
                    type: .readinessReport,
                    payload: readiness.payload.merging([
                        "prediction_blocked": "true",
                        "block_reason": "readiness_gate"
                    ]) { current, _ in current },
                    workspaceTopologyVersion: environment.topology.version
                )
            )
            return
        }
        append(
            .init(
                type: .prediction,
                confidence: 0.5,
                payload: PredictionBuilder().build(events: events),
                workspaceTopologyVersion: environment.topology.version
            )
        )
    }

    private func updatePersonalBaselines(from events: [ObserverEvent]) {
        let dates = events.map(\.timestamp)
        let observedHours: Double?
        if let start = dates.min(), let end = dates.max() {
            observedHours = try? environment.observationCalendarStore.observedHours(since: start, until: end)
        } else {
            observedHours = nil
        }
        let samples = PersonalBaselineBuilder().samples(
            from: events,
            observedHours: observedHours,
            includeOverrides: environment.settings.workSchedule.includeOverridesInBaselines
        )
        for sample in samples {
            try? environment.personalBaselineStore.upsert(sample: sample)
        }
    }

    private func startMediaTimer() {
        guard scheduleGate.status().sensorAllowed else {
            return
        }
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
        currentMediaListenSession = nil
        headphoneOutputTransitionGate.reset()
        lastAudioActive = nil
        lastAudioActivityEventAt = nil
        isMediaProbeInFlight = false
        isMediaActionInFlight = false
    }

    private func sampleMediaPlayback() {
        guard scheduleGate.status().sensorAllowed else {
            return
        }
        handleAudioOutputTransition()
        recordAudioActivityStateIfNeeded()

        guard !isMediaProbeInFlight else {
            return
        }
        isMediaProbeInFlight = true
        let probe = MediaPlaybackService().currentPlaybackProbe()
        isMediaProbeInFlight = false
        consumeMediaPlaybackProbe(probe)
    }

    private func consumeMediaPlaybackProbe(_ probe: MediaPlaybackService.ProbeResult) {
        guard scheduleGate.status().sensorAllowed else {
            return
        }
        guard let snapshot = probe.snapshot else {
            recordMediaProbeResultWithoutSnapshotIfNeeded(probe.failures)
            return
        }

        let now = Date()
        let userAppearsAway = userAppearsAwayForMediaPreference()
        updateMediaListenSession(
            snapshot,
            now: now,
            userAppearsAway: userAppearsAway,
            activeAppName: currentFocus?.appName
        )

        guard snapshot.identityKey != lastMediaPlaybackKey else {
            return
        }

        var payload = snapshot.eventPayload
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
            activityInsight: nil,
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

    private func performMediaAction(
        _ operation: (MediaPlaybackService) -> [String],
        completion: ([String]) -> Void
    ) {
        guard !isMediaActionInFlight else {
            return
        }
        isMediaActionInFlight = true
        let result = operation(MediaPlaybackService())
        isMediaActionInFlight = false
        completion(result)
    }

    private func updateMediaListenSession(
        _ snapshot: MediaPlaybackSnapshot,
        now: Date,
        userAppearsAway: Bool,
        activeAppName: String?
    ) {
        guard snapshot.state == "playing" else {
            currentMediaListenSession = nil
            return
        }

        let trackKey = snapshot.trackIdentityKey
        let inputActive = (latestInputActivity?.secondsSinceAnyInput ?? .greatestFiniteMagnitude) <= 20

        if currentMediaListenSession?.trackKey != trackKey {
            currentMediaListenSession = MediaListenSession(
                trackKey: trackKey,
                startedAt: now,
                lastSeenAt: now,
                observationSamples: 1,
                inputActiveSamples: inputActive ? 1 : 0,
                lastProfileEventAt: nil
            )
            return
        }

        guard var session = currentMediaListenSession else {
            return
        }

        session.lastSeenAt = now
        session.observationSamples += 1
        if inputActive {
            session.inputActiveSamples += 1
        }

        let listenSeconds = now.timeIntervalSince(session.startedAt)
        let canEmit = session.lastProfileEventAt.map { now.timeIntervalSince($0) >= 300 } ?? true
        if canEmit,
           let reaction = MediaReactionBuilder().sustainedListenReaction(
                current: snapshot,
                listenSeconds: listenSeconds,
                observationSamples: session.observationSamples,
                userAppearsAway: userAppearsAway,
                inputActiveDuringTrack: session.inputActiveSamples >= 3,
                activeAppName: activeAppName
           ) {
            session.lastProfileEventAt = now
            append(
                .init(
                    type: .mediaReaction,
                    confidence: reaction.confidence,
                    payload: reaction.payload,
                    workspaceTopologyVersion: environment.topology.version
                )
            )
        }

        currentMediaListenSession = session
    }

    private func recordMediaProbeResultWithoutSnapshotIfNeeded(_ failures: [String], now: Date = Date()) {
        guard lastMediaProbeFailureAt.map({ now.timeIntervalSince($0) >= 120 }) ?? true else {
            return
        }

        lastMediaProbeFailureAt = now
        append(
            .init(
                type: .mediaPlayback,
                payload: [
                    "action": failures.isEmpty ? "media_probe_no_active_source" : "media_probe_failed",
                    "status": failures.isEmpty ? "players_closed_or_not_playing" : "probe_error",
                    "failures": failures.prefix(4).joined(separator: " | "),
                    "display_eligible": "false"
                ],
                workspaceTopologyVersion: environment.topology.version
            )
        )
        notifyStateChanged()
    }

    private func userAppearsAwayForMediaPreference() -> Bool {
        consecutiveMissingFaceSamples >= 4
            && (latestInputActivity?.secondsSinceAnyInput ?? 0) >= 45
    }

    private func recordAudioActivityStateIfNeeded(now: Date = Date()) {
        let audio = AudioOutputService()
        guard let active = audio.isAudioActive() else {
            return
        }
        let stateChanged = lastAudioActive != active
        let minuteElapsed = lastAudioActivityEventAt.map { now.timeIntervalSince($0) >= 60 } ?? true
        guard stateChanged || minuteElapsed else {
            return
        }
        lastAudioActive = active
        lastAudioActivityEventAt = now
        append(
            .init(
                type: .mediaPlayback,
                confidence: 0.92,
                payload: [
                    "source": "system_audio",
                    "state": active ? "playing" : "stopped",
                    "audio_active": active ? "true" : "false",
                    "sensor_tier": "tier1_output_activity",
                    "track_identified": "false",
                    "display_eligible": "false"
                ],
                workspaceTopologyVersion: environment.topology.version
            )
        )
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
        let transition = headphoneOutputTransitionGate.observe(
            outputLooksLikeHeadphones: outputName.map(audioService.looksLikeHeadphones),
            now: Date()
        )

        switch transition {
        case .none:
            return
        case .returned:
            resumeMediaIfHeadphonesReturned(outputName: outputName)
        case .removed:
            pauseMediaAfterHeadphonesRemoved(
                reason: "audio_output_headphones_removed_confirmed",
                outputName: outputName,
                now: Date()
            )
        }
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

        let sources = autoPausedSources
        performMediaAction({ $0.resumeSources(sources) }) { [weak self] resumedSources in
            guard let self, !resumedSources.isEmpty else { return }
            self.autoPausedSources = []
            self.latestHint = "Медиа: наушники вернулись, продолжил"
            self.lastHintAt = Date()
            self.append(
                .init(
                    type: .mediaPlayback,
                    payload: [
                        "action": "auto_resume",
                        "reason": "headphones_returned",
                        "resumed_sources": resumedSources.joined(separator: ", "),
                        "audio_output": outputName ?? "unknown"
                    ],
                    workspaceTopologyVersion: self.environment.topology.version
                )
            )
            self.notifyStateChanged()
        }
    }

    private func updateHeadphoneWearState(from snapshot: AttentionSnapshot, now: Date = Date()) {
        let genericHeadphoneConfidence = snapshot.visualObjects
            .compactMap { observation -> Double? in
                guard ObjectPresenceBuilder().normalizedClass(from: observation.label) == "headphones" else {
                    return nil
                }
                return observation.confidence
            }
            .max()
        let audioOutputIndicatesHeadphones = AudioOutputService().currentOutputName()
            .map { AudioOutputService().looksLikeHeadphones($0) } ?? false
        headphoneAppearanceService.observe(
            jpegData: snapshot.jpegData,
            facePresent: snapshot.facePresent,
            faceCenterX: snapshot.faceCenterX,
            faceCenterY: snapshot.faceCenterY,
            faceArea: snapshot.faceArea,
            genericHeadphoneConfidence: genericHeadphoneConfidence,
            audioOutputIndicatesHeadphones: audioOutputIndicatesHeadphones,
            confirmedWearing: headphoneWearStateMachine.isWearing == true
        ) { [weak self] visualState in
            guard let self, self.mode == .observing else { return }
            let transition = self.headphoneWearStateMachine.observe(
                facePresent: snapshot.facePresent,
                visualState: visualState,
                now: now
            )
            switch transition {
            case .none:
                return
            case .removed:
                self.pauseMediaAfterHeadphonesRemoved(
                    reason: "camera_headphones_removed_profile_confirmed",
                    outputName: AudioOutputService().currentOutputName(),
                    now: now
                )
            case .putOn:
                self.resumeMediaIfHeadphonesWornAgain(now: now)
            }
        }
    }

    private func pauseMediaAfterHeadphonesRemoved(
        reason: String,
        outputName: String?,
        now: Date = Date()
    ) {
        guard environment.settings.autoPauseMediaWhenAway else {
            return
        }
        guard mode == .observing else {
            return
        }
        guard lastHeadphonesAutoPauseAt.map({ now.timeIntervalSince($0) >= 30 }) ?? true else {
            return
        }

        let audioActiveNow = AudioOutputService().isAudioActive() == true
        let mediaSource = lastMediaPlaybackSnapshot?.state == "playing"
            ? lastMediaPlaybackSnapshot?.source
            : ((lastAudioActive == true || audioActiveNow)
                ? "System Media Key"
                : recentMediaPageTracker.recentSource(now: now))
        guard let mediaSource else {
            return
        }

        performMediaAction({ $0.pauseAllKnownSources() }) { [weak self] pausedSources in
            guard let self else { return }
            guard !pausedSources.isEmpty else {
                self.latestHint = "Медиа: снял наушники, не удалось отправить паузу"
                self.lastHintAt = now
                self.append(
                    .init(
                        type: .mediaPlayback,
                        payload: [
                            "action": "auto_pause_skipped",
                            "reason": reason,
                            "audio_output": outputName ?? "unknown",
                            "source": mediaSource
                        ],
                        workspaceTopologyVersion: self.environment.topology.version
                    )
                )
                self.notifyStateChanged()
                return
            }

            self.lastHeadphonesAutoPauseAt = now
            self.lastAutoPauseAt = now
            self.autoPausedSources = pausedSources
            self.latestHint = "Медиа: снял наушники, команда паузы отправлена"
            self.lastHintAt = now
            self.append(
                .init(
                    type: .mediaPlayback,
                    payload: [
                        "action": "auto_pause",
                        "reason": reason,
                        "pause_actor": "observer",
                        "paused_sources": pausedSources.joined(separator: ", "),
                        "audio_output": outputName ?? "unknown",
                        "source": mediaSource,
                        "command_confirmed": "false"
                    ],
                    workspaceTopologyVersion: self.environment.topology.version
                )
            )
            self.verifyHeadphoneMediaPause(
                reason: reason,
                source: mediaSource,
                outputName: outputName,
                requestedAt: now
            )
            self.notifyStateChanged()
        }
    }

    private func verifyHeadphoneMediaPause(
        reason: String,
        source: String,
        outputName: String?,
        requestedAt: Date
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.mode == .observing else { return }
            let audioStillActive = AudioOutputService().isAudioActive() == true
            self.lastAudioActive = audioStillActive
            self.append(
                .init(
                    type: .mediaPlayback,
                    confidence: audioStillActive ? 0.45 : 0.9,
                    payload: [
                        "action": "auto_pause_verification",
                        "reason": reason,
                        "source": source,
                        "audio_output": outputName ?? "unknown",
                        "audio_active_after_seconds": "2",
                        "audio_still_active": audioStillActive ? "true" : "false",
                        "requested_at": ISO8601DateFormatter().string(from: requestedAt)
                    ],
                    workspaceTopologyVersion: self.environment.topology.version
                )
            )
            self.latestHint = audioStillActive
                ? "Медиа: после паузы звук ещё активен"
                : "Медиа: команда паузы отправлена"
            self.lastHintAt = Date()
            self.notifyStateChanged()
        }
    }

    private func resumeMediaIfHeadphonesWornAgain(now: Date = Date()) {
        guard environment.settings.autoResumeMediaWhenBack,
              !autoPausedSources.isEmpty,
              latestAttention?.facePresent == true,
              let lastAutoPauseAt,
              now.timeIntervalSince(lastAutoPauseAt) <= 1800
        else {
            return
        }

        let sources = autoPausedSources
        performMediaAction({ $0.resumeSources(sources) }) { [weak self] resumedSources in
            guard let self, !resumedSources.isEmpty else { return }
            self.autoPausedSources = []
            self.latestHint = "Медиа: наушники вернулись, продолжил"
            self.lastHintAt = now
            self.append(
                .init(
                    type: .mediaPlayback,
                    payload: [
                        "action": "auto_resume",
                        "reason": "camera_headphones_worn_profile_confirmed",
                        "resumed_sources": resumedSources.joined(separator: ", ")
                    ],
                    workspaceTopologyVersion: self.environment.topology.version
                )
            )
            self.notifyStateChanged()
        }
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

        let mediaSource = lastMediaPlaybackSnapshot?.state == "playing"
            ? lastMediaPlaybackSnapshot?.source
            : (lastAudioActive == true
                ? "System Media Key"
                : recentMediaPageTracker.recentSource(now: Date()))
        guard let mediaSource else {
            return
        }

        let now = Date()
        guard lastAutoPauseAt.map({ now.timeIntervalSince($0) >= 60 }) ?? true else {
            return
        }

        performMediaAction({ $0.pauseAllKnownSources() }) { [weak self] pausedSources in
            guard let self, !pausedSources.isEmpty else { return }
            self.lastAutoPauseAt = now
            self.autoPausedSources = pausedSources
            self.append(
                .init(
                    type: .mediaPlayback,
                    payload: [
                        "action": "auto_pause",
                        "reason": fullyAway ? "away_from_computer" : "listener_not_visible",
                        "paused_sources": pausedSources.joined(separator: ", "),
                        "missing_face_samples": "\(self.consecutiveMissingFaceSamples)",
                        "seconds_since_any_input": String(format: "%.1f", inputIdleSeconds),
                        "source": mediaSource,
                        "command_confirmed": "false"
                    ],
                    workspaceTopologyVersion: self.environment.topology.version
                )
            )
        }
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

        let sources = autoPausedSources
        performMediaAction({ $0.resumeSources(sources) }) { [weak self] resumedSources in
            guard let self, !resumedSources.isEmpty else { return }
            self.autoPausedSources = []
            self.append(
                .init(
                    type: .mediaPlayback,
                    payload: [
                        "action": "auto_resume",
                        "reason": "user_returned",
                        "resumed_sources": resumedSources.joined(separator: ", "),
                        "audio_output": outputName ?? "unknown"
                    ],
                    workspaceTopologyVersion: self.environment.topology.version
                )
            )
        }
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
    let securityIncidentCount: Int
    let calibration: WidgetCalibrationState
}

struct WidgetCalibrationState: Equatable {
    let displays: [WidgetCalibrationDisplay]
    let predictedDisplayIndex: Int?
    let predictedCellIndex: Int?
    let predictionText: String
}

struct WidgetCalibrationDisplay: Equatable {
    let index: Int
    let title: String
    let columns: Int
    let rows: Int
    let predictedCell: Int?
}

extension ObserverController.Mode {
    var displayText: String {
        switch self {
        case .offHours:
            return "Off hours"
        case .paused:
            return "Paused"
        case .observing:
            return "Watching"
        }
    }
}

private extension AppFocusSnapshot {
    var isObserverApp: Bool {
        let haystack = [
            appName,
            appID ?? ""
        ]
        .joined(separator: " ")
        .lowercased()
        return haystack.contains("observer")
    }

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

    var isJiraContext: Bool {
        [
            appName,
            appID ?? "",
            windowTitle ?? ""
        ]
        .joined(separator: " ")
        .lowercased()
        .containsAny([
            "jira",
            "atlassian",
            "issue navigator",
            "issues"
        ])
    }
}

private extension WorkspaceTopology.DisplayRole {
    var shortDisplayName: String {
        switch self {
        case .mainWorkbench:
            return "Основной"
        case .productivity:
            return "Ноутбук"
        case .reference:
            return "Реф."
        case .communication:
            return "Связь"
        case .unknown:
            return "Экран"
        }
    }
}

private extension AttentionSnapshot {
    var looksLikePhoneAttention: Bool {
        guard facePresent, !isTemporarilyLostFace else {
            return false
        }
        if let yaw, abs(yaw) > 0.70 {
            return false
        }
        if let leftPupilY, let rightPupilY {
            // Vision's eye coordinates are camera-relative. For this side-camera
            // setup a downward look moves the pupil centroid toward the lower band.
            let pupilY = (leftPupilY + rightPupilY) / 2
            if pupilY >= 0.60 {
                return true
            }
        }
        if let pitch, pitch < -0.25 {
            return true
        }
        return false
    }
}

private extension String {
    func containsAny(_ needles: [String]) -> Bool {
        needles.contains { contains($0) }
    }
}
