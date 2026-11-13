import SwiftUI

/// A cream card with a thin pixel-art outline: square corners cut in two
/// small steps, in warm charcoal brown, and optionally a stepped speech-bubble
/// tail under its bottom edge. Ced's message in the healing room uses the
/// tail; the Grow with Kindness cards use the plain box.
struct PixelBubble: View {
    /// Outline color and thickness, shared by every pixel card.
    static let outline = Color(hex: 0x57463B)
    static let lineWidth: CGFloat = 2.5
    /// One pixel step of the corners and the tail, in points.
    static let step: CGFloat = 3
    /// How far the tail reaches below the box (three steps).
    static let tailHeight: CGFloat = 3 * step

    /// Where the tail's tip is, in points from the box's leading edge; nil
    /// for no tail. The tail's straight side is on the right, so it points
    /// down and to the right, toward something below and right of it.
    var tailTipX: CGFloat?
    var fill = Color(hex: RoomPalette.cardFill)

    var body: some View {
        Canvas { context, size in
            let boxHeight = size.height - (tailTipX == nil ? 0 : Self.tailHeight)
            let path = Self.outlinePath(width: size.width, boxHeight: boxHeight, tailTipX: tailTipX)
            context.fill(path, with: .color(fill))
            context.stroke(path, with: .color(Self.outline),
                           style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .square, lineJoin: .miter))
        }
        .accessibilityHidden(true)
    }

    /// The stepped outline, inset by half the line width so the whole stroke
    /// stays inside the view.
    static func outlinePath(width: CGFloat, boxHeight: CGFloat, tailTipX: CGFloat?) -> Path {
        let i = lineWidth / 2, s = step
        let left = i, top = i, right = width - i, bottom = boxHeight - i
        var points: [CGPoint] = [
            // Top edge, then the top-right corner in two steps.
            CGPoint(x: left + 2 * s, y: top), CGPoint(x: right - 2 * s, y: top),
            CGPoint(x: right - 2 * s, y: top + s), CGPoint(x: right - s, y: top + s),
            CGPoint(x: right - s, y: top + 2 * s), CGPoint(x: right, y: top + 2 * s),
            // Right edge, then the bottom-right corner.
            CGPoint(x: right, y: bottom - 2 * s), CGPoint(x: right - s, y: bottom - 2 * s),
            CGPoint(x: right - s, y: bottom - s), CGPoint(x: right - 2 * s, y: bottom - s),
            CGPoint(x: right - 2 * s, y: bottom),
        ]
        if let tip = tailTipX {
            // Along the bottom edge to the tail: straight down on its right,
            // stepping back up and left on its other side.
            let tipX = min(max(tip, left + 6 * s), right - 3 * s)
            points += [
                CGPoint(x: tipX, y: bottom), CGPoint(x: tipX, y: bottom + 3 * s),
                CGPoint(x: tipX - s, y: bottom + 3 * s), CGPoint(x: tipX - s, y: bottom + 2 * s),
                CGPoint(x: tipX - 2 * s, y: bottom + 2 * s), CGPoint(x: tipX - 2 * s, y: bottom + s),
                CGPoint(x: tipX - 3 * s, y: bottom + s), CGPoint(x: tipX - 3 * s, y: bottom),
            ]
        }
        points += [
            // Bottom-left corner, left edge, top-left corner.
            CGPoint(x: left + 2 * s, y: bottom), CGPoint(x: left + 2 * s, y: bottom - s),
            CGPoint(x: left + s, y: bottom - s), CGPoint(x: left + s, y: bottom - 2 * s),
            CGPoint(x: left, y: bottom - 2 * s), CGPoint(x: left, y: top + 2 * s),
            CGPoint(x: left + s, y: top + 2 * s), CGPoint(x: left + s, y: top + s),
            CGPoint(x: left + 2 * s, y: top + s),
        ]
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}
