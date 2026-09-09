import SwiftUI

/// The Claude Code mark, translated directly from its 24x24 SVG path data
/// (two "eye" cutouts use the even-odd fill rule, matching the source
/// SVG's `fill-rule="evenodd"`) so it renders crisply at any size without
/// bundling an image asset.
struct ClaudeCodeMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }

        var path = Path()

        // Outer frame
        path.move(to: pt(20.998, 10.949))
        path.addLine(to: pt(24, 10.949))
        path.addLine(to: pt(24, 14.051))
        path.addLine(to: pt(21, 14.051))
        path.addLine(to: pt(21, 17.079))
        path.addLine(to: pt(19.513, 17.079))
        path.addLine(to: pt(19.513, 20))
        path.addLine(to: pt(18, 20))
        path.addLine(to: pt(18, 17.079))
        path.addLine(to: pt(16.513, 17.079))
        path.addLine(to: pt(16.513, 20))
        path.addLine(to: pt(15, 20))
        path.addLine(to: pt(15, 17.079))
        path.addLine(to: pt(9, 17.079))
        path.addLine(to: pt(9, 20))
        path.addLine(to: pt(7.488, 20))
        path.addLine(to: pt(7.488, 17.079))
        path.addLine(to: pt(6, 17.079))
        path.addLine(to: pt(6, 20))
        path.addLine(to: pt(4.487, 20))
        path.addLine(to: pt(4.487, 17.079))
        path.addLine(to: pt(3, 17.079))
        path.addLine(to: pt(3, 14.05))
        path.addLine(to: pt(0, 14.05))
        path.addLine(to: pt(0, 10.95))
        path.addLine(to: pt(3, 10.95))
        path.addLine(to: pt(3, 5))
        path.addLine(to: pt(20.998, 5))
        path.closeSubpath()

        // Left eye cutout
        path.move(to: pt(6, 10.949))
        path.addLine(to: pt(7.488, 10.949))
        path.addLine(to: pt(7.488, 8.102))
        path.addLine(to: pt(6, 8.102))
        path.closeSubpath()

        // Right eye cutout
        path.move(to: pt(16.51, 10.949))
        path.addLine(to: pt(18, 10.949))
        path.addLine(to: pt(18, 8.102))
        path.addLine(to: pt(16.51, 8.102))
        path.closeSubpath()

        return path
    }
}
