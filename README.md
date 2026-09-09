# CCBar

CCBar is a lightweight macOS menu bar app that shows your [Claude Code](https://claude.com/claude-code) usage — session and weekly rate-limit consumption — at a glance, without you having to run `claude /usage` yourself.

It lives quietly in the menu bar, refreshes every 5 minutes, and expands into a small popover with session/weekly/Opus usage rings when you click it.

## Why

Claude Code's CLI usage limits (session window + weekly window) are only visible if you run `/usage` inside a `claude` session. CCBar surfaces that same information persistently in the menu bar so you can see how close you are to a limit without interrupting your work.

## How it works

CCBar gets usage data from two sources, and prefers the authoritative one whenever it's available:

1. **`claude -p "/usage"` (authoritative)** — [`ClaudeCLIUsageReader`](Sources/CCBarCore/Services/ClaudeCLIUsageReader.swift) shells out to your already-authenticated `claude` CLI and parses its plain-text `/usage` output for the real session and weekly percentages straight from Anthropic. This never touches your OAuth token or makes a network call itself — the `claude` process does that on its own.
2. **Local JSONL logs (fallback + Opus split)** — [`JSONLScanner`](Sources/CCBarCore/Services/JSONLScanner.swift) incrementally tail-reads Claude Code's own local session logs (`~/.claude/projects/**/*.jsonl` and the Xcode Coding Assistant equivalent), tracking a byte offset per file so it only parses newly-appended lines on each scan. [`UsageWindowCalculator`](Sources/CCBarCore/Services/UsageWindowCalculator.swift) sums token counts into rolling 5-hour (session) and 7-day (weekly) windows. This is used as a fallback if the CLI command isn't available (not installed, not signed in, timed out), and also to estimate what *fraction* of your weekly usage was Opus — since `/usage` doesn't report that split, CCBar applies the locally-derived Opus fraction to the authoritative weekly percentage.

[`AccountInfoReader`](Sources/CCBarCore/Services/AccountInfoReader.swift) additionally reads your account email and plan tier (Pro / Max 5x / Max 20x / Team) from `~/.claude.json` — deliberately narrow, it only decodes those two fields and never touches credential material (which lives in the Keychain, not that file).

[`UsageStore`](Sources/CCBarCore/Services/UsageStore.swift) ties these together: on a 5-minute timer it re-scans logs, re-runs `/usage`, and recomputes the published session/weekly/Opus percentages that drive the UI. Scanned events and file offsets are cached to disk (`~/Library/Application Support/CCBar/`) so a relaunch doesn't lose history or re-parse everything from scratch.

## UI

- **Menu bar item** — a compact usage indicator ([`StatusItemContentView`](Sources/CCBarApp/Views/StatusItemContentView.swift)).
- **Popover panel** — click the menu bar item to expand a small panel ([`ExpandedPanelView`](Sources/CCBarApp/Views/ExpandedPanelView.swift)) with usage rings ([`UsageRing`](Sources/CCBarApp/Views/UsageRing.swift), [`UsageRow`](Sources/CCBarApp/Views/UsageRow.swift)) for session, weekly, and Opus-weekly usage, along with reset times and account/plan info.
- **Right-click** the menu bar item for a Quit option.

All of this is built with AppKit + SwiftUI, run as a menu-bar-only accessory app (no Dock icon, no regular windows) via [`AppDelegate`](Sources/CCBarApp/AppDelegate.swift) and [`StatusItemController`](Sources/CCBarApp/StatusItemController.swift).

## Project structure

```
Sources/
  CCBarCore/            # Platform-agnostic logic, no UI
    Models/
      UsageEvent.swift          # A single parsed usage line (tokens, model, timestamp)
    Services/
      JSONLScanner.swift        # Incremental reader for Claude Code's local JSONL logs
      ClaudeCLIUsageReader.swift# Shells out to `claude -p "/usage"` for authoritative %s
      UsageWindowCalculator.swift # Rolling session/weekly window math over UsageEvents
      AccountInfoReader.swift   # Reads email/plan from ~/.claude.json
      UsageStore.swift          # Ties the above together; @Published state for the UI
  CCBarApp/              # macOS app target (AppKit + SwiftUI)
    AppDelegate.swift
    StatusItemController.swift  # Menu bar item + popover lifecycle
    Views/
      StatusItemContentView.swift
      ExpandedPanelView.swift
      UsageRing.swift
      UsageRow.swift
      ClaudeCodeMark.swift
      VisualEffectView.swift
    main.swift
  CCBarAppTests/         # Test entry point
```

## Requirements

- macOS 13 (Ventura) or later
- Swift 5.9+ / Xcode command line tools
- [Claude Code](https://claude.com/claude-code) installed and signed in (for live `/usage` data — CCBar falls back to local log estimates otherwise)

## Building

CCBar is a Swift Package Manager project — no Xcode project file needed.

```bash
swift build -c release
```

To build and assemble a double-clickable `CCBar.app` bundle (including ad-hoc code signing and, if `Sources/CCBarApp/Resources/AppIcon.png` exists, an app icon):

```bash
./build-app.sh
```

This produces `CCBar.app` in the project root. Move it to `/Applications` and launch it, or just double-click it in place.

## Running from source

```bash
swift run CCBarApp
```

## Privacy

CCBar reads only local files it needs (Claude Code's own JSONL session logs and `~/.claude.json`) and shells out to the `claude` CLI you already have installed and authenticated. It never reads your OAuth token, never talks to any network endpoint itself, and doesn't send data anywhere beyond what the `claude` CLI already does on your behalf.

## License

No license specified yet — all rights reserved by default.
