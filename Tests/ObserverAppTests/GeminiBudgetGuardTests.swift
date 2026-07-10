import Foundation
import Testing
@testable import ObserverApp

struct GeminiBudgetGuardTests {
    @Test func allowsRequestUnderDailyBudget() {
        let now = Date()
        let decision = GeminiBudgetGuard().evaluate(
            events: [
                request(cost: 0.50, timestamp: now),
                request(cost: 0.25, timestamp: now)
            ],
            now: now,
            budgetEUR: 2.0,
            estimatedCostPerRequestEUR: 0.02
        )

        #expect(decision.allowed)
        #expect(decision.spentTodayEUR == 0.75)
    }

    @Test func blocksProjectedOverspend() {
        let now = Date()
        let decision = GeminiBudgetGuard().evaluate(
            events: [
                request(cost: 1.99, timestamp: now)
            ],
            now: now,
            budgetEUR: 2.0,
            estimatedCostPerRequestEUR: 0.02
        )

        #expect(!decision.allowed)
        #expect(decision.projectedSpendEUR == 2.01)
    }

    @Test func ignoresYesterdaySpend() {
        let now = Date()
        let decision = GeminiBudgetGuard().evaluate(
            events: [
                request(cost: 2.0, timestamp: now.addingTimeInterval(-90_000))
            ],
            now: now,
            budgetEUR: 2.0,
            estimatedCostPerRequestEUR: 0.02
        )

        #expect(decision.allowed)
        #expect(decision.spentTodayEUR == 0)
    }

    private func request(cost: Double, timestamp: Date) -> ObserverEvent {
        ObserverEvent(
            id: UUID(),
            timestamp: timestamp,
            type: .externalLLMRequest,
            source: "observer_app",
            platform: "macOS",
            displayRole: nil,
            appID: nil,
            confidence: 1,
            payload: [
                "provider": "gemini",
                "estimated_cost_eur": "\(cost)"
            ],
            workspaceTopologyVersion: 1
        )
    }
}
