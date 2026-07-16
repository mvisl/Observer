import Foundation
import Testing
@testable import ObserverApp

struct HeadphoneOutputTransitionGateTests {
    @Test func requiresTwoStableNonHeadphoneOutputProbesBeforeRemoval() {
        var gate = HeadphoneOutputTransitionGate(confirmationSeconds: 5)
        let start = Date()

        #expect(gate.observe(outputLooksLikeHeadphones: true, now: start) == .none)
        #expect(gate.observe(outputLooksLikeHeadphones: false, now: start.addingTimeInterval(10)) == .none)
        #expect(gate.observe(outputLooksLikeHeadphones: false, now: start.addingTimeInterval(14)) == .none)
        #expect(gate.observe(outputLooksLikeHeadphones: false, now: start.addingTimeInterval(16)) == .removed)
    }

    @Test func unknownAudioOutputCannotCausePause() {
        var gate = HeadphoneOutputTransitionGate()
        let start = Date()

        #expect(gate.observe(outputLooksLikeHeadphones: true, now: start) == .none)
        #expect(gate.observe(outputLooksLikeHeadphones: nil, now: start.addingTimeInterval(10)) == .none)
        #expect(gate.observe(outputLooksLikeHeadphones: nil, now: start.addingTimeInterval(40)) == .none)
        #expect(gate.observe(outputLooksLikeHeadphones: true, now: start.addingTimeInterval(50)) == .none)
    }

    @Test func headphoneReturnIsImmediateOnlyAfterKnownOutputChange() {
        var gate = HeadphoneOutputTransitionGate()
        let start = Date()

        #expect(gate.observe(outputLooksLikeHeadphones: false, now: start) == .none)
        #expect(gate.observe(outputLooksLikeHeadphones: true, now: start.addingTimeInterval(10)) == .returned)
    }
}
