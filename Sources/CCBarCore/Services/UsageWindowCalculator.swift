import Foundation

public struct UsageLimits: Codable, Equatable {
    public var sessionTokenBudget: Int
    public var weeklyTokenBudget: Int

    public init(sessionTokenBudget: Int, weeklyTokenBudget: Int) {
        self.sessionTokenBudget = sessionTokenBudget
        self.weeklyTokenBudget = weeklyTokenBudget
    }

    // Placeholder guesses — Anthropic doesn't publish exact per-plan token
    // budgets. These were back-calculated from one account's real raw
    // token counts against the percentages claude.ai actually reported at
    // calibration time (session 4%, weekly 29%, the latter under a
    // temporary +50% weekly boost active through 2026-09-13) — not a
    // universal number for all plans/usage patterns. Recalibrate in
    // Settings against `claude /usage` if these drift.
    public static let `default` = UsageLimits(sessionTokenBudget: 8_810_787_000, weeklyTokenBudget: 5_541_188_000)
}

public struct WindowResult: Equatable {
    public let percent: Double
    public let resetsAt: Date
}

public enum UsageWindowCalculator {
    public static let sessionWindowSeconds: TimeInterval = 5 * 3600
    public static let weeklyWindowSeconds: TimeInterval = 7 * 24 * 3600

    /// Raw (not percent-of-budget) token totals for the current weekly
    /// window — used to derive what *fraction* of the week's usage was
    /// Opus, which can then be applied against an authoritative weekly
    /// percentage from an external source instead of our own guessed budget.
    public static func rawWeeklyTotals(events: [UsageEvent], now: Date = Date()) -> (total: Int, opus: Int) {
        let windowStart = now.addingTimeInterval(-weeklyWindowSeconds)
        let weekEvents = events.filter { $0.timestamp >= windowStart && $0.timestamp <= now }
        let total = weekEvents.reduce(0) { $0 + $1.totalTokens }
        let opus = weekEvents.filter { $0.isOpus }.reduce(0) { $0 + $1.totalTokens }
        return (total, opus)
    }

    public static func computeSessionWindow(
        events: [UsageEvent],
        limits: UsageLimits,
        now: Date = Date()
    ) -> WindowResult {
        computeWindow(
            events: events,
            windowSeconds: sessionWindowSeconds,
            budget: limits.sessionTokenBudget,
            now: now,
            filter: { _ in true }
        )
    }

    public static func computeWeeklyWindow(
        events: [UsageEvent],
        limits: UsageLimits,
        now: Date = Date()
    ) -> WindowResult {
        computeWindow(
            events: events,
            windowSeconds: weeklyWindowSeconds,
            budget: limits.weeklyTokenBudget,
            now: now,
            filter: { _ in true }
        )
    }

    public static func computeOpusWeeklyWindow(
        events: [UsageEvent],
        limits: UsageLimits,
        now: Date = Date()
    ) -> WindowResult {
        computeWindow(
            events: events,
            windowSeconds: weeklyWindowSeconds,
            budget: limits.weeklyTokenBudget,
            now: now,
            filter: { $0.isOpus }
        )
    }

    // MARK: - Shared helpers

    private static func computeWindow(
        events: [UsageEvent],
        windowSeconds: TimeInterval,
        budget: Int,
        now: Date,
        filter: (UsageEvent) -> Bool
    ) -> WindowResult {
        let windowStart = now.addingTimeInterval(-windowSeconds)
        let matching = events.filter { $0.timestamp >= windowStart && $0.timestamp <= now && filter($0) }
        let total = matching.reduce(0) { $0 + $1.totalTokens }
        let pct = percent(total, of: budget)

        let resetsAt: Date
        if let earliest = matching.map({ $0.timestamp }).min() {
            resetsAt = earliest.addingTimeInterval(windowSeconds)
        } else {
            resetsAt = now
        }

        return WindowResult(percent: pct, resetsAt: resetsAt)
    }

    private static func percent(_ total: Int, of budget: Int) -> Double {
        guard budget > 0 else { return 0 }
        return max(0, Double(total) / Double(budget) * 100)
    }
}
