import Foundation

struct AttentionStateBuilder {
    func build(
        attention: AttentionSnapshot?,
        input: InputActivitySnapshot?,
        settings: ObserverSettings
    ) -> String {
        guard let attention else {
            return "Контекст: камера выключена"
        }

        guard attention.facePresent else {
            return "Контекст: не у экрана"
        }

        if let input, input.secondsSinceAnyInput >= settings.readingPauseSecondsForDisplay {
            return "Контекст: думает / читает"
        }

        if let input, input.secondsSinceAnyInput < 15 {
            return "Контекст: активно работает"
        }

        if let yaw = attention.yaw {
            if yaw > 0.45 {
                return "Контекст: смотрит в сторону"
            }
            if yaw < -0.45 {
                return "Контекст: смотрит в сторону"
            }
        }

        return "Контекст: смотрит на экран"
    }
}

private extension ObserverSettings {
    var readingPauseSecondsForDisplay: Double {
        min(detectorSettings.readingPauseSeconds, 180)
    }
}
