import AppKit
import SwiftUI
import CCBarCore

/// The full usage panel shown in the menu bar dropdown.
struct ExpandedPanelView: View {
    static let panelWidth: CGFloat = 320

    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider

            UsageRow(
                iconName: "clock",
                label: "Current session",
                percent: store.sessionPercent,
                metaText: "Resets \(store.sessionResetsText)"
            )
            .padding(.vertical, 10)
            divider

            UsageRow(
                iconName: "calendar",
                label: "Weekly usage",
                percent: store.weeklyPercent,
                metaText: "Resets \(store.weeklyResetsText)"
            )
            .padding(.vertical, 10)
            divider

            UsageRow(
                iconName: "sparkles",
                label: "Weekly Opus usage",
                percent: store.opusPercent,
                metaText: "Resets \(store.weeklyResetsText) \u{00B7} share of weekly, estimated"
            )
            .padding(.vertical, 10)
            divider

            footer
                .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: Self.panelWidth, alignment: .top)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                ClaudeCodeMark()
                    .fill(Color.primary, style: FillStyle(eoFill: true))
                    .frame(width: 14, height: 14)
                Text("Claude Usage")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(store.planLabel)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            if let email = store.accountEmail {
                Text(email)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .padding(.leading, 22)
            }
        }
        .padding(.bottom, 12)
    }

    private var divider: some View {
        Divider()
    }

    private var footer: some View {
        HStack {
            Button(action: { Task { await store.refresh() } }) {
                Text("Refresh")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary.opacity(0.85))

            Spacer()

            Text("Updated \(relativeUpdatedText)")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)

            Divider().frame(height: 10)

            Button(action: { NSApp.terminate(nil) }) {
                Text("Quit")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }

    private var relativeUpdatedText: String {
        guard let lastUpdated = store.lastUpdated else { return "never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastUpdated, relativeTo: Date())
    }
}
