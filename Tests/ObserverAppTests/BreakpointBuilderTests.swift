import Foundation
import Testing
@testable import ObserverApp

struct BreakpointBuilderTests {
    @Test func createsFinePauseOnlyAfterThreshold() {
        let builder = BreakpointBuilder()

        #expect(builder.fineInputPause(secondsSinceAnyInput: 20) == nil)

        let payload = builder.fineInputPause(secondsSinceAnyInput: 31)
        #expect(payload?["level"] == "fine")
        #expect(payload?["reason"] == "input_pause")
    }

    @Test func coarseIdleBreakpointRequestsSummaryTrigger() {
        let payload = BreakpointBuilder().coarseIdleStart(secondsSinceAnyInput: 301)

        #expect(payload["level"] == "coarse")
        #expect(payload["summary_trigger"] == "true")
    }
}
