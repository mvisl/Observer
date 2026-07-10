import Foundation

struct GeminiBudgetDecision: Equatable {
    let allowed: Bool
    let spentTodayEUR: Double
    let projectedSpendEUR: Double
    let budgetEUR: Double
}

struct GeminiBudgetGuard {
    func evaluate(
        events: [ObserverEvent],
        now: Date = Date(),
        budgetEUR: Double,
        estimatedCostPerRequestEUR: Double,
        calendar: Calendar = .current
    ) -> GeminiBudgetDecision {
        let spent = spentToday(events: events, now: now, calendar: calendar)
        let projected = spent + estimatedCostPerRequestEUR
        return GeminiBudgetDecision(
            allowed: projected <= budgetEUR,
            spentTodayEUR: spent,
            projectedSpendEUR: projected,
            budgetEUR: budgetEUR
        )
    }

    private func spentToday(
        events: [ObserverEvent],
        now: Date,
        calendar: Calendar
    ) -> Double {
        events.reduce(0) { total, event in
            guard event.type == .externalLLMRequest else {
                return total
            }
            guard event.payload["provider"] == "gemini" else {
                return total
            }
            guard calendar.isDate(event.timestamp, inSameDayAs: now) else {
                return total
            }
            guard let cost = event.payload["estimated_cost_eur"].flatMap(Double.init) else {
                return total
            }
            return total + cost
        }
    }
}
