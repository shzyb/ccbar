import Foundation

public struct CLIUsageSnapshot: Equatable {
    public let sessionPercent: Double?
    public let sessionResetsText: String?
    public let weeklyPercent: Double?
    public let weeklyResetsText: String?
}

/// Gets authoritative usage percentages by shelling out to the `claude`
/// CLI's own `/usage` command, rather than estimating from local token
/// counts against a guessed budget. This never touches the OAuth token or
/// makes a network call itself — the already-authenticated `claude`
/// process does that on its own, and we only read its plain-text stdout.
public enum ClaudeCLIUsageReader {
    private static let timeout: TimeInterval = 15

    public static func read() -> CLIUsageSnapshot {
        guard let output = runUsageCommand() else {
            return CLIUsageSnapshot(sessionPercent: nil, sessionResetsText: nil, weeklyPercent: nil, weeklyResetsText: nil)
        }
        return parse(output)
    }

    private static func runUsageCommand() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // A login shell (-l) picks up PATH customizations (nvm, homebrew,
        // etc.) the same way the user's own terminal would, since the
        // `claude` binary's location isn't guaranteed.
        process.arguments = ["-l", "-c", "claude -p \"/usage\""]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        // Discarded, but still must go *somewhere* other than an unread
        // Pipe — otherwise a full stderr buffer would block the child the
        // same way an undrained stdout pipe would.
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // Enforced even if the process never exits on its own. A
        // terminate() here always leaves terminationStatus non-zero (it's
        // delivered as SIGTERM), so the exit-status check below already
        // covers the timeout case without needing a separate flag.
        let timeoutWorkItem = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

        // readDataToEndOfFile continuously drains the pipe as output
        // arrives, rather than waiting until the process exits to read
        // anything — so a larger-than-expected amount of output can never
        // deadlock the child by filling the pipe buffer while nothing is
        // reading it.
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeoutWorkItem.cancel()

        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func parse(_ output: String) -> CLIUsageSnapshot {
        let (sessionPercent, sessionResets) = extract(
            from: output,
            pattern: #"Current session:\s*(\d+)%\s*used\s*(?:·\s*resets\s*(.+))?"#
        )
        let (weeklyPercent, weeklyResets) = extract(
            from: output,
            pattern: #"Current week[^:]*:\s*(\d+)%\s*used\s*(?:·\s*resets\s*(.+))?"#
        )
        return CLIUsageSnapshot(
            sessionPercent: sessionPercent,
            sessionResetsText: sessionResets,
            weeklyPercent: weeklyPercent,
            weeklyResetsText: weeklyResets
        )
    }

    private static func extract(from text: String, pattern: String) -> (Double?, String?) {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return (nil, nil)
        }

        var percent: Double?
        if match.range(at: 1).location != NSNotFound, let range = Range(match.range(at: 1), in: text) {
            percent = Double(text[range])
        }

        var resetsText: String?
        if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound, let range = Range(match.range(at: 2), in: text) {
            resetsText = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return (percent, resetsText)
    }
}
