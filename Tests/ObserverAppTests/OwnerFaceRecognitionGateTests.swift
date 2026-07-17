import Testing
@testable import ObserverApp

struct OwnerFaceRecognitionGateTests {
    @Test func unknownProfileCannotDismissAVisitorIncident() {
        let recognizer = OwnerFaceRecognizer()
        let result = recognizer.isOwnerFace(
            AttentionSnapshot(
                facePresent: true,
                attentionZone: .nearCamera,
                facePosition: .center,
                confidence: 0.8,
                faceCount: 1,
                faceCenterX: 0.5,
                faceCenterY: 0.5,
                faceArea: 0.05,
                yaw: nil,
                pitch: nil,
                roll: nil
            )
        )

        #expect(result == nil)
    }

    @Test func multipleFacesCannotDismissAVisitorIncident() {
        let recognizer = OwnerFaceRecognizer()
        let result = recognizer.isOwnerFace(
            AttentionSnapshot(
                facePresent: true,
                attentionZone: .nearCamera,
                facePosition: .center,
                confidence: 0.8,
                faceCount: 2,
                faceCenterX: 0.5,
                faceCenterY: 0.5,
                faceArea: 0.05,
                yaw: nil,
                pitch: nil,
                roll: nil
            )
        )

        #expect(result == nil)
    }
}
