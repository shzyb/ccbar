import Foundation

@MainActor
public final class UsageStore: ObservableObject {
    @Published public private(set) var sessionPercent: Double = 0
    @Published public private(set) var weeklyPercent: Double = 0
    @Published public private(set) var opusPercent: Double = 0
    @Published public private(set) var sessionResetsText: String = "\u{2014}"
    @Published public private(set) var weeklyResetsText: String = "\u{2014}"
    @Published public private(set) var isLiveData: Bool = false
    @Published public private(set) var lastUpdated: Date?
    @Published public private(set) var isRefreshing: Bool = false
    @Published public private(set) var planLabel: String = "Unknown plan"
    @Published public private(set) var accountEmail: String?

    /// Fallback budgets used only if the `claude` CLI's own `/usage`
    /// command is unavailable (not installed, not signed in, timed out) —
    /// these are rough local guesses, never the primary source of truth.
    public var limits: UsageLimits {
        didSet { recompute() }
    }

    /// How many days of trend/history to retain in memory. Bounded so
    /// long-running sessions don't accumulate unbounded event history.
    private let retentionDays = 8

    private let scanner: JSONLScanner
    private var events: [UsageEvent] = []
    private let eventsCacheURL: URL
    private var lastCLISnapshot = CLIUsageSnapshot(
        sessionPercent: nil, sessionResetsText: nil, weeklyPercent: nil, weeklyResetsText: nil
    )

    public init(
        scanner: JSONLScanner = JSONLScanner(),
        limits: UsageLimits = .default,
        eventsCacheURL: URL? = nil
    ) {
        self.scanner = scanner
        self.limits = limits
        self.eventsCacheURL = eventsCacheURL ?? Self.defaultEventsCacheURL()
        applyAccountInfo(AccountInfoReader.read())

        // The scanner persists file *offsets* across launches so it never
        // re-reads content it's already seen, but that means a fresh
        // launch would otherwise start with an empty in-memory `events`
        // array and only see whatever gets appended *after* this launch —
        // silently losing days of already-scanned history. Restoring the
        // last cached snapshot here keeps window sums correct across
        // restarts.
        self.events = Self.loadCachedEvents(from: self.eventsCacheURL)
    }

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        async let newEventsTask: [UsageEvent] = Task.detached(priority: .utility) { [scanner] in
            scanner.scanNewEvents()
        }.value
        async let accountInfoTask = Task.detached(priority: .utility) {
            AccountInfoReader.read()
        }.value
        async let cliSnapshotTask = Task.detached(priority: .utility) {
            ClaudeCLIUsageReader.read()
        }.value

        let newEvents = await newEventsTask
        applyAccountInfo(await accountInfoTask)
        lastCLISnapshot = await cliSnapshotTask

        events.append(contentsOf: newEvents)
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 24 * 3600)
        events.removeAll { $0.timestamp < cutoff }

        recompute()
        lastUpdated = Date()
        saveCachedEvents()
    }

    private func applyAccountInfo(_ info: AccountInfo) {
        accountEmail = info.emailAddress
        planLabel = info.planLabel ?? "Unknown plan"
    }

    private func recompute() {
        let now = Date()

        // The `claude` CLI's own `/usage` command is the authoritative
        // source — it reflects Anthropic's real rate limits directly,
        // rather than our own guess at a token budget. Only fall back to
        // the local estimate if that command failed or isn't available.
        let localSession = UsageWindowCalculator.computeSessionWindow(events: events, limits: limits, now: now)
        let localWeekly = UsageWindowCalculator.computeWeeklyWindow(events: events, limits: limits, now: now)

        if let cliSession = lastCLISnapshot.sessionPercent, let cliWeekly = lastCLISnapshot.weeklyPercent {
            isLiveData = true
            sessionPercent = cliSession
            weeklyPercent = cliWeekly
            sessionResetsText = lastCLISnapshot.sessionResetsText ?? "unknown"
            weeklyResetsText = lastCLISnapshot.weeklyResetsText ?? "unknown"
        } else {
            isLiveData = false
            sessionPercent = localSession.percent
            weeklyPercent = localWeekly.percent
            sessionResetsText = "in \(formattedDuration(until: localSession.resetsAt, now: now)) (estimated)"
            weeklyResetsText = "in \(formattedDuration(until: localWeekly.resetsAt, now: now)) (estimated)"
        }

        // There's no separate "Opus-only" figure from `/usage`, so derive
        // it as a share of the authoritative weekly percentage: use local
        // logs only to find what *fraction* of this week's raw tokens were
        // Opus, then apply that fraction to the real weekly percent. This
        // keeps the total anchored to truth even though the split is an
        // estimate.
        let rawWeekly = UsageWindowCalculator.rawWeeklyTotals(events: events, now: now)
        let opusFraction = rawWeekly.total > 0 ? Double(rawWeekly.opus) / Double(rawWeekly.total) : 0
        opusPercent = weeklyPercent * opusFraction
    }

    private func formattedDuration(until date: Date, now: Date) -> String {
        let interval = max(0, date.timeIntervalSince(now))
        let totalMinutes = Int(interval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private static func defaultEventsCacheURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? home.appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("CCBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("events-cache.json")
    }

    private static func loadCachedEvents(from url: URL) -> [UsageEvent] {
        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode([UsageEvent].self, from: data) else {
            return []
        }
        return cached
    }

    private func saveCachedEvents() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: eventsCacheURL, options: .atomic)
    }
}
