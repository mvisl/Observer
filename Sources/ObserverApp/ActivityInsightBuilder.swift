import Foundation

struct ActivityInsightBuilder {
    func build(
        attention: AttentionSnapshot?,
        input: InputActivitySnapshot?,
        topology: WorkspaceTopology,
        currentFocus: AppFocusSnapshot?,
        currentFocusStartedAt: Date?,
        focusChangesLastMinute: Int,
        now: Date = Date()
    ) -> String {
        let presence = presenceSignal(attention, input: input)
        let focusSeconds = currentFocusStartedAt.map { max(0, now.timeIntervalSince($0)) }
        let intent = currentFocus.map(AppIntent.init(focus:)) ?? .unknown
        let workspace = workspaceSignal(input: input, currentFocus: currentFocus)

        if intent == .lockScreen {
            if presence == .away || attention?.facePresent == false {
                return "Защита: отошёл и прикрыл экран"
            }
            return "Защита: экран заблокирован"
        }

        if focusChangesLastMinute >= 4 {
            if intent == .socialFeed {
                return "Соцсети: быстро переключает ленту"
            }
            if intent == .browser {
                return "Веб-контекст: переключает вкладки"
            }
            return "Поиск / сравнение: много переключений"
        }

        if let attention,
           let input,
           input.secondsSinceAnyInput >= 45,
           attention.isStrongPhoneLook {
            return "\(intent.prefix): смотрит в телефон"
        }

        if let attention, attention.isLookingAway {
            if input?.secondsSinceAnyInput ?? .greatestFiniteMagnitude < 20 {
                return "\(intent.prefix): отвлекся от экрана"
            }
            if let input, input.secondsSinceAnyInput >= 45, attention.isStrongPhoneLook {
                return "\(intent.prefix): смотрит в телефон"
            }
            return "\(intent.prefix): смотрит вне экрана"
        }

        if let input, input.secondsSinceAnyInput >= 120 {
            if attention?.facePresent == true || attention?.isTemporarilyLostFace == true {
                return "\(intent.readingPrefix): \(formatDuration(input.secondsSinceAnyInput)) без ввода"
            }
            return "\(intent.prefix): долгая пауза"
        }

        if let input, input.secondsSinceAnyInput < 15 {
            if let focusSeconds, focusSeconds >= 180 {
                return "\(intent.prefix): устойчиво в задаче"
            }
            if let workspace {
                return "\(intent.activePrefix): \(workspace)"
            }
            return intent.activeText
        }

        if let input, input.secondsSinceAnyInput < 75 {
            if let attention, attention.facePresent || attention.isTemporarilyLostFace {
                let zone = attention.readingZoneHint
                return zone == "экран" ? intent.readingPrefix : "\(intent.readingPrefix): \(zone)"
            }
            return "\(intent.prefix): микропауза \(formatDuration(input.secondsSinceAnyInput))"
        }

        if let focusSeconds, focusSeconds >= 300 {
            return "\(intent.prefix): долго в одном контексте"
        }

        return "\(intent.prefix): читает"
    }

    private func workspaceSignal(
        input: InputActivitySnapshot?,
        currentFocus: AppFocusSnapshot?
    ) -> String? {
        guard let input, input.secondsSinceAnyInput < 15 else {
            return nil
        }

        let activeRole = input.mouseDisplayRole ?? currentFocus?.displayRole
        switch activeRole {
        case .mainWorkbench:
            return nil
        case .productivity:
            return nil
        case .reference:
            return "референсы"
        case .communication:
            return "коммуникации"
        case .unknown, .none:
            return nil
        }
    }

    private enum PresenceSignal {
        case present
        case uncertain
        case away
    }

    private func presenceSignal(
        _ attention: AttentionSnapshot?,
        input: InputActivitySnapshot?
    ) -> PresenceSignal {
        guard let attention else {
            return .uncertain
        }

        if attention.isTemporarilyLostFace {
            return .present
        }

        guard attention.facePresent else {
            if let input, input.secondsSinceAnyInput < 900 {
                return .uncertain
            }
            return .away
        }

        return .present
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return "\(Int(seconds))с"
        }
        return "\(Int(seconds / 60))м"
    }
}

private enum AppIntent {
    case aiAssistant
    case design
    case code
    case browser
    case socialFeed
    case communication
    case meeting
    case service
    case lockScreen
    case unknown

    init(focus: AppFocusSnapshot) {
        let haystack = [
            focus.appName,
            focus.appID ?? "",
            focus.windowTitle ?? ""
        ].joined(separator: " ").lowercased()

        if haystack.contains("loginwindow") || haystack.contains("lock screen") {
            self = .lockScreen
        } else if haystack.contains("chatgpt") || haystack.contains("openai") || haystack.contains("claude") || haystack.contains("gemini") {
            self = .aiAssistant
        } else if haystack.contains("figma") || haystack.contains("sketch") {
            self = .design
        } else if haystack.contains("xcode") || haystack.contains("visual studio code") || haystack.contains("cursor") || haystack.contains("terminal") {
            self = .code
        } else if Self.isSocialFeed(haystack) {
            self = .socialFeed
        } else if haystack.contains("slack")
            || haystack.contains("telegram")
            || haystack.contains("viber")
            || haystack.contains("whatsapp")
            || haystack.contains("messages")
            || haystack.contains("mail") {
            self = .communication
        } else if haystack.contains("chrome") || haystack.contains("safari") || haystack.contains("firefox") {
            self = .browser
        } else if haystack.contains("zoom") || haystack.contains("meet") || haystack.contains("teams") {
            self = .meeting
        } else if haystack.contains("finder") || haystack.contains("system settings") || haystack.contains("settings") {
            self = .service
        } else {
            self = .unknown
        }
    }

    private static func isSocialFeed(_ haystack: String) -> Bool {
        [
            "instagram",
            "facebook",
            "fb.com",
            "x.com",
            "twitter",
            "threads",
            "tiktok",
            "reddit",
            "linkedin",
            "pinterest",
            "vk.com",
            "vkontakte",
            "ok.ru",
            "одноклассники"
        ].contains { haystack.contains($0) }
    }

    var prefix: String {
        switch self {
        case .aiAssistant:
            return "Диалог с ИИ"
        case .design:
            return "Дизайн"
        case .code:
            return "Код"
        case .browser:
            return "Веб-контекст"
        case .socialFeed:
            return "Соцсети"
        case .communication:
            return "Коммуникация"
        case .meeting:
            return "Встреча"
        case .service:
            return "Сервисная настройка"
        case .lockScreen:
            return "Защита"
        case .unknown:
            return "Рабочий контекст"
        }
    }

    var activeText: String {
        switch self {
        case .aiAssistant:
            return "Диалог с ИИ: формулирует задачу"
        case .design:
            return "Дизайн: правит макет"
        case .code:
            return "Код: активная правка"
        case .browser:
            return "Веб-контекст: просматривает страницу"
        case .socialFeed:
            return "Соцсети: просматривает ленту"
        case .communication:
            return "Коммуникация: отвечает"
        case .meeting:
            return "Встреча: активное участие"
        case .service:
            return "Сервисная настройка"
        case .lockScreen:
            return "Защита: экран заблокирован"
        case .unknown:
            return "Рабочий контекст: активные действия"
        }
    }

    var activePrefix: String {
        switch self {
        case .aiAssistant:
            return "Диалог с ИИ"
        case .design:
            return "Дизайн"
        case .code:
            return "Код"
        case .browser:
            return "Веб-контекст"
        case .socialFeed:
            return "Соцсети"
        case .communication:
            return "Коммуникация"
        case .meeting:
            return "Встреча"
        case .service:
            return "Сервисная настройка"
        case .lockScreen:
            return "Защита"
        case .unknown:
            return "Работа"
        }
    }

    var readingPrefix: String {
        switch self {
        case .aiAssistant:
            return "Диалог с ИИ: читает ответ"
        case .design:
            return "Дизайн: рассматривает макет"
        case .code:
            return "Код: читает / думает"
        case .browser:
            return "Веб-контекст: читает"
        case .socialFeed:
            return "Соцсети: читает / смотрит ленту"
        case .communication:
            return "Коммуникация: читает"
        case .meeting:
            return "Встреча: слушает"
        case .service:
            return "Сервисная настройка: пауза"
        case .lockScreen:
            return "Защита: экран заблокирован"
        case .unknown:
            return "Глубокое чтение"
        }
    }

    var downwardIdleOverridesScreenReading: Bool {
        switch self {
        case .aiAssistant, .code:
            return false
        case .design, .browser, .socialFeed, .communication, .meeting, .service, .unknown, .lockScreen:
            return true
        }
    }
}

private extension AttentionSnapshot {
    var isLookingAway: Bool {
        guard facePresent else {
            return false
        }
        if let yaw, abs(yaw) > 0.55 {
            return true
        }
        return attentionZone == .offScreen
    }

    var isStrongPhoneLook: Bool {
        guard facePresent else {
            return false
        }
        if isTemporarilyLostFace {
            return false
        }
        if let leftPupilY, let rightPupilY, (leftPupilY + rightPupilY) / 2 <= 0.30 {
            return true
        }
        if let pitch, pitch < -0.25 {
            return true
        }
        return false
    }

    var isDownwardIdleCandidate: Bool {
        guard facePresent else {
            return false
        }
        if let pitch, pitch < -0.14 {
            return true
        }
        if let faceCenterY, faceCenterY <= 0.34 {
            return true
        }
        if let eyeContactScore, eyeContactScore <= 0.34 {
            return true
        }
        return false
    }

    var readingZoneHint: String {
        guard facePresent || isTemporarilyLostFace else {
            return "экран"
        }

        if let faceCenterY {
            if faceCenterY <= 0.35 {
                return "нижняя часть экрана"
            }
            if faceCenterY >= 0.68 {
                return "верхняя часть экрана"
            }
        }

        return "экран"
    }
}
