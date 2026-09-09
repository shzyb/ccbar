import Foundation
import CCBarCore

// A tiny dependency-free test runner. This machine only has the Xcode
// Command Line Tools installed (no full Xcode.app), so neither XCTest
// nor the Testing module are available — both ship as part of Xcode.app.
// If you install Xcode.app later, this can be replaced by a proper
// `swift test` target; until then this exercises the same window-math
// and JSONL-parsing logic with plain assertions.

var failureCount = 0

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    if condition() {
        print("PASS: \(name)")
    } else {
        print("FAIL: \(name)")
        failureCount += 1
    }
}

func approximatelyEqual(_ a: Double, _ b: Double, tolerance: Double = 0.001) -> Bool {
    abs(a - b) < tolerance
}

func makeEvent(hoursAgo: Double, tokens: Int, now: Date, model: String = "claude-sonnet-5") -> UsageEvent {
    UsageEvent(
        timestamp: now.addingTimeInterval(-hoursAgo * 3600),
        model: model,
        inputTokens: tokens,
        outputTokens: 0,
        cacheCreationTokens: 0,
        cacheReadTokens: 0
    )
}

// MARK: - Session window

do {
    let now = Date()
    let events = [
        makeEvent(hoursAgo: 1, tokens: 1000, now: now),
        makeEvent(hoursAgo: 4, tokens: 500, now: now),
        makeEvent(hoursAgo: 6, tokens: 999_999, now: now) // outside 5h window
    ]
    let limits = UsageLimits(sessionTokenBudget: 1500, weeklyTokenBudget: 100_000)
    let result = UsageWindowCalculator.computeSessionWindow(events: events, limits: limits, now: now)
    check("sessionWindowSumsOnlyEventsInLastFiveHours", approximatelyEqual(result.percent, 100.0))
}

// MARK: - Weekly window

do {
    let now = Date()
    let events = [
        makeEvent(hoursAgo: 24, tokens: 1000, now: now),
        makeEvent(hoursAgo: 24 * 10, tokens: 5000, now: now) // outside 7d window
    ]
    let limits = UsageLimits(sessionTokenBudget: 100_000, weeklyTokenBudget: 2000)
    let result = UsageWindowCalculator.computeWeeklyWindow(events: events, limits: limits, now: now)
    check("weeklyWindowExcludesEventsOlderThanSevenDays", approximatelyEqual(result.percent, 50.0))
}

// MARK: - Opus weekly window

do {
    let now = Date()
    let events = [
        makeEvent(hoursAgo: 1, tokens: 1000, now: now, model: "claude-opus-4-6"),
        makeEvent(hoursAgo: 1, tokens: 1000, now: now, model: "claude-sonnet-4-6")
    ]
    let limits = UsageLimits(sessionTokenBudget: 100_000, weeklyTokenBudget: 2000)
    let result = UsageWindowCalculator.computeOpusWeeklyWindow(events: events, limits: limits, now: now)
    check("opusWeeklyWindowOnlyCountsOpusModels", approximatelyEqual(result.percent, 50.0))
}

// MARK: - Percent not clamped above 100

do {
    let now = Date()
    let events = [makeEvent(hoursAgo: 0, tokens: 3000, now: now)]
    let limits = UsageLimits(sessionTokenBudget: 1000, weeklyTokenBudget: 100_000)
    let result = UsageWindowCalculator.computeSessionWindow(events: events, limits: limits, now: now)
    check("percentIsNotClampedAboveOneHundred", approximatelyEqual(result.percent, 300.0))
}

// MARK: - Zero budget does not crash

do {
    let now = Date()
    let events = [makeEvent(hoursAgo: 0, tokens: 100, now: now)]
    let limits = UsageLimits(sessionTokenBudget: 0, weeklyTokenBudget: 0)
    let result = UsageWindowCalculator.computeSessionWindow(events: events, limits: limits, now: now)
    check("zeroBudgetDoesNotCrashOrDivideByZero", result.percent == 0.0)
}

// MARK: - JSONLScanner: parsing + incremental offset tracking

do {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ccbar-test-\(UUID().uuidString)")
    let projectsDir = tempDir.appendingPathComponent("projects/fake-project")
    try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let logFile = projectsDir.appendingPathComponent("session1.jsonl")
    let firstBatch = [
        #"{"type":"user","timestamp":"2026-08-21T07:00:00.000Z"}"#,
        #"{"type":"assistant","timestamp":"2026-08-21T07:00:08.178Z","message":{"model":"claude-sonnet-5","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":5,"cache_read_input_tokens":2}}}"#,
        "this is not valid json at all"
    ]
    try (firstBatch.joined(separator: "\n") + "\n").write(to: logFile, atomically: true, encoding: .utf8)

    let scanner = JSONLScanner(
        baseDirectories: [projectsDir],
        stateFileURL: tempDir.appendingPathComponent("state/scan-state.json")
    )

    let firstEvents = scanner.scanNewEvents()
    check("scannerReturnsExactlyOneValidEventFromFirstBatch", firstEvents.count == 1)
    check("scannerParsesModelCorrectly", firstEvents.first?.model == "claude-sonnet-5")
    check("scannerSumsTokenFieldsCorrectly", firstEvents.first?.totalTokens == 10 + 20 + 5 + 2)

    check("scannerReturnsNothingOnRepeatScanWithNoNewData", scanner.scanNewEvents().count == 0)

    let handle = try FileHandle(forWritingTo: logFile)
    handle.seekToEndOfFile()
    let secondLine = #"{"type":"assistant","timestamp":"2026-08-21T08:00:00.000Z","message":{"model":"claude-opus-4-6","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"# + "\n"
    handle.write(secondLine.data(using: .utf8)!)
    try handle.close()

    let secondEvents = scanner.scanNewEvents()
    check("scannerReturnsOnlyNewlyAppendedEventOnIncrementalScan", secondEvents.count == 1)
    check("scannerParsesSecondEventModelCorrectly", secondEvents.first?.model == "claude-opus-4-6")
    check("scannerFlagsOpusModelCorrectly", secondEvents.first?.isOpus == true)
}

print("")
if failureCount == 0 {
    print("All tests passed.")
    exit(0)
} else {
    print("\(failureCount) test(s) failed.")
    exit(1)
}
