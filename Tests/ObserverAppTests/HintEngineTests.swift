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
        #expect(hint?.contains("возвращается") == true)
    }

    @Test func doesNotSurfaceGenericQuietMode() {
        let detection = DetectorEngine.Detection(
            name: "reading_or_thinking",
            confidence: 0.8,
            payload: ["detector": "reading_or_thinking"]
        )

        #expect(HintEngine().hint(for: detection) == nil)
    }
}
