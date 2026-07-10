import Foundation

struct HintEngine {
    func hint(for detection: DetectorEngine.Detection) -> String? {
        switch detection.name {
        case "frequent_app_switching":
            return "Context is switching a lot. Collect context before asking another model."

        case "return_loop":
            return "You keep returning to the same context. Capture the blocker while it is fresh."

        case "reading_or_thinking":
            return "Quiet mode: this looks like reading or thinking."

        default:
            return nil
        }
    }
}
