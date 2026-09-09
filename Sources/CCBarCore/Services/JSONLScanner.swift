import Foundation
import os.log

/// Reads Claude Code's local JSONL usage logs incrementally, tracking a
/// byte offset per file so repeated scans only parse newly-appended lines.
public final class JSONLScanner {
    private static let logger = Logger(subsystem: "com.ccbar.app", category: "JSONLScanner")
    private static let chunkSize = 1 << 20 // 1 MB

    private struct ScanState: Codable {
        var offsets: [String: UInt64] = [:]
    }

    private let baseDirectories: [URL]
    private let stateFileURL: URL
    private var state: ScanState

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public convenience init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultDirs = [
            home.appendingPathComponent(".claude/projects", isDirectory: true),
            home.appendingPathComponent(
                "Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/projects",
                isDirectory: true
            )
        ]
        let appSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? home.appendingPathComponent("Library/Application Support")
        let ccbarDir = appSupport.appendingPathComponent("CCBar", isDirectory: true)
        self.init(baseDirectories: defaultDirs, stateFileURL: ccbarDir.appendingPathComponent("scan-state.json"))
    }

    /// Testable initializer allowing injection of arbitrary base
    /// directories and an isolated scan-state file.
    public init(baseDirectories: [URL], stateFileURL: URL) {
        self.baseDirectories = baseDirectories
        self.stateFileURL = stateFileURL
        try? FileManager.default.createDirectory(
            at: stateFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        state = JSONLScanner.loadState(from: stateFileURL)
    }

    /// Scans all known base directories for .jsonl files and returns any
    /// events found since the last scan. Safe to call repeatedly/on a timer.
    public func scanNewEvents() -> [UsageEvent] {
        var events: [UsageEvent] = []
        for baseDir in baseDirectories {
            for fileURL in jsonlFiles(under: baseDir) {
                events.append(contentsOf: readNewEvents(from: fileURL, baseDir: baseDir))
            }
        }
        saveState()
        return events
    }

    // MARK: - Directory traversal

    private func jsonlFiles(under baseDir: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: baseDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var results: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            results.append(url)
        }
        return results
    }

    // MARK: - Incremental reading

    private func readNewEvents(from fileURL: URL, baseDir: URL) -> [UsageEvent] {
        // Resolve symlinks and refuse to read anything that escapes the
        // expected base directory (defends against a malicious symlink
        // planted inside ~/.claude/projects pointing elsewhere on disk).
        let resolvedFile = fileURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedBase = baseDir.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedFile.path.hasPrefix(resolvedBase.path + "/") else {
            Self.logger.warning("Skipping file outside expected base directory: \(fileURL.path, privacy: .public)")
            return []
        }

        let key = resolvedFile.path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: key),
              let fileSize = (attrs[.size] as? NSNumber)?.uint64Value else {
            return []
        }

        var offset = state.offsets[key] ?? 0
        if offset > fileSize {
            // File was truncated/rewritten since we last read it.
            offset = 0
        }
        guard offset < fileSize else { return [] }

        guard let handle = try? FileHandle(forReadingFrom: resolvedFile) else {
            Self.logger.warning("Could not open file for reading: \(key, privacy: .public)")
            return []
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: offset)
        } catch {
            Self.logger.warning("Could not seek in file: \(key, privacy: .public)")
            return []
        }

        var events: [UsageEvent] = []
        var pendingLine = Data()
        var bytesConsumed: UInt64 = 0
        var lastCompleteLineEnd: UInt64 = offset

        while true {
            guard let chunk = try? handle.read(upToCount: Self.chunkSize), !chunk.isEmpty else {
                break
            }
            pendingLine.append(chunk)
            bytesConsumed += UInt64(chunk.count)

            while let newlineRange = pendingLine.range(of: Data([0x0A])) {
                let lineData = pendingLine.subdata(in: pendingLine.startIndex..<newlineRange.lowerBound)
                pendingLine.removeSubrange(pendingLine.startIndex..<newlineRange.upperBound)
                lastCompleteLineEnd += UInt64(lineData.count) + 1

                if let event = Self.parseEvent(from: lineData) {
                    events.append(event)
                }
            }
        }
        // Any bytes left in `pendingLine` are an incomplete trailing line
        // (e.g. the process was killed mid-write) — leave them unconsumed
        // so the next scan re-reads and completes them.

        state.offsets[key] = lastCompleteLineEnd
        return events
    }

    private static func parseEvent(from lineData: Data) -> UsageEvent? {
        guard !lineData.isEmpty else { return nil }

        struct RawUsage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let cache_creation_input_tokens: Int?
            let cache_read_input_tokens: Int?
        }
        struct RawMessage: Decodable {
            let model: String?
            let usage: RawUsage?
        }
        struct RawLine: Decodable {
            let type: String?
            let timestamp: String?
            let message: RawMessage?
        }

        let raw: RawLine
        do {
            raw = try JSONDecoder().decode(RawLine.self, from: lineData)
        } catch {
            logger.debug("Skipping malformed JSONL line: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        guard raw.type == "assistant",
              let message = raw.message,
              let usage = message.usage,
              let model = message.model,
              let timestampString = raw.timestamp else {
            return nil
        }

        guard let date = isoFormatter.date(from: timestampString)
            ?? isoFormatterNoFraction.date(from: timestampString) else {
            logger.debug("Skipping line with unparsable timestamp: \(timestampString, privacy: .public)")
            return nil
        }

        return UsageEvent(
            timestamp: date,
            model: model,
            inputTokens: usage.input_tokens ?? 0,
            outputTokens: usage.output_tokens ?? 0,
            cacheCreationTokens: usage.cache_creation_input_tokens ?? 0,
            cacheReadTokens: usage.cache_read_input_tokens ?? 0
        )
    }

    // MARK: - Persisted scan state

    private static func loadState(from url: URL) -> ScanState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(ScanState.self, from: data) else {
            return ScanState()
        }
        return state
    }

    private func saveState() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateFileURL, options: .atomic)
    }
}
