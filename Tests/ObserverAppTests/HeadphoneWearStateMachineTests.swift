import Testing
@testable import ObserverApp

struct HeadphoneWearStateMachineTests {
    @Test func requiresTemporalConfirmationBeforePausingOrResuming() {
        var state = HeadphoneWearStateMachine()

        #expect(state.observe(facePresent: true, headphoneConfidence: 0.8) == .none)
        #expect(state.observe(facePresent: true, headphoneConfidence: 0.8) == .none)
        #expect(state.isWearing == true)

        #expect(state.observe(facePresent: true, headphoneConfidence: nil) == .none)
        #expect(state.observe(facePresent: true, headphoneConfidence: nil) == .removed)
        #expect(state.isWearing == false)

        #expect(state.observe(facePresent: true, headphoneConfidence: 0.9) == .none)
        #expect(state.observe(facePresent: true, headphoneConfidence: 0.9) == .putOn)
    }

    @Test func faceLossCannotPretendHeadphonesWereRemoved() {
        var state = HeadphoneWearStateMachine()
        _ = state.observe(facePresent: true, headphoneConfidence: 0.9)
        _ = state.observe(facePresent: true, headphoneConfidence: 0.9)

        #expect(state.observe(facePresent: false, headphoneConfidence: nil) == .none)
        #expect(state.isWearing == true)
    }
}
