import SwiftUI

private struct TextHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 16
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct UsageRow: View {
    let iconName: String
    let label: String
    let percent: Double
    let metaText: String

    @State private var percentTextHeight: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    // Sized to exactly match the rendered height of the
                    // percentage text next to it, measured live rather
                    // than eyeballed, so it stays in sync if that text's
                    // font ever changes.
                    UsageRing(percent: percent, diameter: percentTextHeight, lineWidth: max(2, percentTextHeight * 0.16))
                    Text("\(clampedPercentForDisplay(percent))%")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundColor(.primary)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(key: TextHeightPreferenceKey.self, value: proxy.size.height)
                            }
                        )
                        .onPreferenceChange(TextHeightPreferenceKey.self) { height in
                            percentTextHeight = height
                        }
                }
            }
            Text(metaText)
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .padding(.leading, 24)
        }
    }
}
