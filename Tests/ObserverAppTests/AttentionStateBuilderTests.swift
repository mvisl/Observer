import Testing
@testable import ObserverApp

struct AttentionStateBuilderTests {
    @Test func describesCameraOff() {
        let text = AttentionStateBuilder().build(
            attention: nil,
            input: nil,
            settings: .defaults
        )
        #expect(text.contains("камера выключена"))
    }

    @Test func describesOffScreen() {
        let attention = AttentionSnapshot(
            facePresent: false,
            attentionZone: .offScreen,
            facePosition: .unknown,
            confidence: 0.8,
            faceCount: 0,
            faceCenterX: nil,
            faceCenterY: nil,
            faceArea: nil,
            yaw: nil,
            pitch: nil,
            roll: nil
        )

        let text = AttentionStateBuilder().build(
            attention: attention,
            input: nil,
            settings: .defaults
        )
        #expect(text.contains("не у экрана"))
    }

    @Test func describesThinking() {
        let attention = AttentionSnapshot(
            facePresent: true,
            attentionZone: .nearCamera,
            facePosition: .center,
            confidence: 0.8,
            faceCount: 1,
            faceCenterX: 0.5,
            faceCenterY: 0.5,
            faceArea: 0.2,
            yaw: nil,
            pitch: nil,
            roll: nil
        )
        let input = InputActivitySnapshot(
            secondsSinceKeyboard: 200,
            secondsSinceMouseMove: 200,
            secondsSinceClick: 200,
            secondsSinceAnyInput: 200
        )

        let text = AttentionStateBuilder().build(
            attention: attention,
            input: input,
            settings: .defaults
        )
        #expect(text.contains("думает"))
    }
}
