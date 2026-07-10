import Foundation

struct HintEngine {
    func hint(for detection: DetectorEngine.Detection) -> String? {
        switch detection.name {
        case "frequent_app_switching":
            return "Фрикция: много переключений, лучше собрать контекст"

        case "return_loop":
            return "Фрикция: возвращается к тому же месту"

        case "reading_or_thinking":
            return nil

        default:
            return nil
        }
    }
}
