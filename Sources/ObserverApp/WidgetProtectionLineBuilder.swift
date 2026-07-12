import Foundation

struct WidgetProtectionLineBuilder {
    func build(
        appName: String?,
        appID: String?,
        facePresent: Bool?,
        missingFaceSamples: Int,
        secondsSinceAnyInput: TimeInterval?
    ) -> String? {
        let identity = [appName, appID]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let isSecuritySurface = identity.contains("securityagent")
            || identity.contains("loginwindow")
            || identity.contains("lock screen")
        let faceMissing = facePresent == false
        let confirmedAway = faceMissing && missingFaceSamples >= 2
        let inputIdle = secondsSinceAnyInput ?? 0

        if isSecuritySurface {
            if faceMissing || missingFaceSamples > 0 || inputIdle >= 20 {
                return "Защита: экран закрыт; тебя нет у компьютера"
            }
            return "Защита: системный экран поверх работы"
        }

        if confirmedAway {
            return "Защита: тебя нет у компьютера; рабочий контекст сохранён"
        }

        if faceMissing && inputIdle < 8 {
            return "Защита: камера потеряла лицо, но ввод ещё активен"
        }

        return nil
    }
}
