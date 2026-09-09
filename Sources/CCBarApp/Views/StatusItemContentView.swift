import SwiftUI
import CCBarCore

/// What's drawn inside the menu bar status item itself: both usage rings
/// side by side, matching the menu bar's own light/dark appearance.
struct StatusItemContentView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(spacing: 5) {
            usageGroup(tag: "5H", percent: store.sessionPercent)
            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 1, height: 12)
            usageGroup(tag: "1W", percent: store.weeklyPercent)
        }
        .padding(.horizontal, 6)
        .fixedSize()
    }

    private func usageGroup(tag: String, percent: Double) -> some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)
            UsageRing(percent: percent, diameter: 14, lineWidth: 2)
            Text("\(clampedPercentForDisplay(percent))%")
                .font(.system(size: 11, weight: .medium, design: .default).monospacedDigit())
                .foregroundColor(.primary)
        }
    }
}
