import Foundation
import Testing
@testable import ObserverApp

struct HeadphoneWearStateMachineTests {
    @Test func requiresTemporalConfirmationBeforePausingOrResuming() {
        var state = HeadphoneWearStateMachine()
        let start = Date()

        #expect(state.observe(facePresent: true, visualState: .wearing(0.8), now: start) == .none)
        #expect(state.observe(facePresent: true, visualState: .wearing(0.8), now: start.addingTimeInterval(5)) == .none)
        #expect(state.isWearing == true)

        #expect(state.observe(facePresent: true, visualState: .unknown, now: start.addingTimeInterval(6)) == .none)
        #expect(state.observe(facePresent: true, visualState: .notWearing(0.8), now: start.addingTimeInterval(7)) == .none)
        #expect(state.observe(facePresent: true, visualState: .notWearing(0.8), now: start.addingTimeInterval(12)) == .removed)
        #expect(state.isWearing == false)

        #expect(state.observe(facePresent: true, visualState: .wearing(0.9), now: start.addingTimeInterval(13)) == .none)
        #expect(state.observe(facePresent: true, visualState: .wearing(0.9), now: start.addingTimeInterval(18)) == .putOn)
    }

    @Test func faceLossCannotPretendHeadphonesWereRemoved() {
        var state = HeadphoneWearStateMachine()
        let start = Date()
        _ = state.observe(facePresent: true, visualState: .wearing(0.9), now: start)
        _ = state.observe(facePresent: true, visualState: .wearing(0.9), now: start.addingTimeInterval(5))

        #expect(state.observe(facePresent: false, visualState: .unknown, now: start.addingTimeInterval(10)) == .none)
        #expect(state.isWearing == true)
    }

    @Test func unknownCameraFramesCannotPretendHeadphonesWereRemoved() {
        var state = HeadphoneWearStateMachine()
        let start = Date()
        _ = state.observe(facePresent: true, visualState: .wearing(0.9), now: start)
        _ = state.observe(facePresent: true, visualState: .wearing(0.9), now: start.addingTimeInterval(5))

        #expect(state.observe(facePresent: true, visualState: .unknown, now: start.addingTimeInterval(10)) == .none)
        #expect(state.observe(facePresent: true, visualState: .unknown, now: start.addingTimeInterval(15)) == .none)
        #expect(state.isWearing == true)
    }

    @Test func removalConfirmsInFiveSecondsWithoutAnyGazeInput() {
        var state = HeadphoneWearStateMachine(confirmationSeconds: 5)
        let start = Date()
        _ = state.observe(facePresent: true, visualState: .wearing(0.9), now: start)
        _ = state.observe(facePresent: true, visualState: .wearing(0.9), now: start.addingTimeInterval(5))

        #expect(state.observe(facePresent: true, visualState: .notWearing(0.9), now: start.addingTimeInterval(20)) == .none)
        #expect(state.observe(facePresent: true, visualState: .notWearing(0.9), now: start.addingTimeInterval(25)) == .removed)
    }

    @Test func briefUnknownFrameDoesNotCancelAVisibleRemoval() {
        var state = HeadphoneWearStateMachine(confirmationSeconds: 5, unknownGraceSeconds: 2)
        let start = Date()
        _ = state.observe(facePresent: true, visualState: .wearing(0.9), now: start)
        _ = state.observe(facePresent: true, visualState: .wearing(0.9), now: start.addingTimeInterval(5))

        #expect(state.observe(facePresent: true, visualState: .notWearing(0.9), now: start.addingTimeInterval(20)) == .none)
        #expect(state.observe(facePresent: true, visualState: .unknown, now: start.addingTimeInterval(21)) == .none)
        #expect(state.observe(facePresent: true, visualState: .notWearing(0.9), now: start.addingTimeInterval(25)) == .removed)
    }
}
