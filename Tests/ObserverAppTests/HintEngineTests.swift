import Testing
@testable import ObserverApp

struct HintEngineTests {
    @Test func mapsDetectorToQuietHint() {
        let detection = DetectorEngine.Detection(
            name: "return_loop",
            confidence: 0.8,
            payload: ["detector": "return_loop"]
        )

        let hint = HintEngine().hint(for: detection)
        #expect(hint?.contains("same context") == true)
    }
}
