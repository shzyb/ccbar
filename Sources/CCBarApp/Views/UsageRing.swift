import SwiftUI

/// Clamps a raw (possibly >100, e.g. an under-calibrated budget) usage
/// percent to a sane display range, so the UI shows "100%" instead of a
/// layout-breaking number like "39333%".
func clampedPercentForDisplay(_ percent: Double) -> Int {
    Int(min(max(percent, 0), 100).rounded())
}

/// Threshold-based color for a usage ring: green under 60%, yellow 60-84%,
/// red 85%+.
func usageRingColor(forPercent percent: Double) -> Color {
    switch percent {
    case ..<60:
        return Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)
    case 60..<85:
        return Color(red: 0xFF / 255, green: 0xD6 / 255, blue: 0x0A / 255)
    default:
        return Color(red: 0xFF / 255, green: 0x45 / 255, blue: 0x3A / 255)
    }
}

struct UsageRing: View {
    let percent: Double
    var diameter: CGFloat = 16
    var lineWidth: CGFloat = 2.5

    private var clampedFraction: Double {
        min(max(percent, 0), 100) / 100
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clampedFraction)
                .stroke(
                    usageRingColor(forPercent: percent),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeInOut(duration: 0.3), value: percent)
    }
}
