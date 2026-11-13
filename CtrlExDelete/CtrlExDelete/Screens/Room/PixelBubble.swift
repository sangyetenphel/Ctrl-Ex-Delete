import SwiftUI

/// A cream card with a pixel-art outline, built from square "pixels" the
/// size of the line width (like a sprite, not a stroked shape). Each corner
/// is a staircase of two big square steps (two pixels across, two down),
/// and an optional speech-bubble tail hangs under the bottom edge with the
/// same steps. Ced's message in the healing room uses the tail; the Grow
/// with Kindness cards use the plain box.
///
///   corner (top-left)        tail (tip on the right)
///   . . . . X X X X          X X X X . . . X X X   ← bottom edge
///   . . . . X                      X . . . X
///   . . X X X                      X X X . X
///   . . X                              X . X
///   X X X                              X X X ← tip
///   X
struct PixelBubble: View {
    /// Outline color (soft charcoal gray), shared by every pixel card.
    static let outline = Color(hex: 0x68686B)
    /// One pixel of the outline, in points: 8 device pixels on a 3× iPhone,
    /// so every block lands on whole device pixels.
    static let pixel: CGFloat = 8.0 / 3.0
    /// How far the tail reaches below the box (four pixels).
    static let tailHeight: CGFloat = 4 * pixel

    /// Where the tail's tip is, in points from the box's leading edge; nil
    /// for no tail. The tail's straight side is on the right, so it points
    /// down and to the right, toward something below and right of it.
    var tailTipX: CGFloat?
    var fill = Color(hex: RoomPalette.cardFill)
    /// When set, paints the empty pixels outside the top-left corner's steps,
    /// and one pixel beyond them to the left and above, in this color, behind
    /// the bubble. The healing room uses the wall's color there: the window
    /// sill and the bookshelf's post sit right behind that corner and would
    /// otherwise touch its outline.
    var topLeftCornerBackdrop: Color? = nil

    var body: some View {
        Canvas { context, size in
            let p = Self.pixel
            let boxHeight = size.height - (tailTipX == nil ? 0 : Self.tailHeight)
            let columns = max(Int(size.width / p), 16)
            let rows = max(Int(boxHeight / p), 12)
            // The few points left over are split evenly on each side,
            // rounded to whole device pixels.
            let x0 = ((size.width - CGFloat(columns) * p) / 2 * 3).rounded(.down) / 3
            let y0 = ((boxHeight - CGFloat(rows) * p) / 2 * 3).rounded(.down) / 3
            let tipColumn = tailTipX.map { Int((($0 - x0) / p).rounded(.down)) }
            let corners = Self.outlinePoints(columns: columns, rows: rows, tailColumn: tipColumn)

            // Fill: the outline traced through the pixels' centers.
            var shape = Path()
            shape.addLines(corners.map { CGPoint(x: x0 + (CGFloat($0.x) + 0.5) * p, y: y0 + (CGFloat($0.y) + 0.5) * p) })
            shape.closeSubpath()
            context.fill(shape, with: .color(fill))

            // Outline: each straight segment as a row or column of whole pixels.
            for (a, b) in zip(corners, corners.dropFirst() + corners.prefix(1)) {
                let rect = CGRect(x: x0 + CGFloat(min(a.x, b.x)) * p, y: y0 + CGFloat(min(a.y, b.y)) * p,
                                  width: CGFloat(abs(a.x - b.x) + 1) * p, height: CGFloat(abs(a.y - b.y) + 1) * p)
                context.fill(Path(rect), with: .color(Self.outline))
            }
        }
        .background(alignment: .topLeading) {
            if let backdrop = topLeftCornerBackdrop {
                cornerGap(backdrop)
            }
        }
        .accessibilityHidden(true)
    }

    /// Behind the bubble (in front of whatever it sits on): the empty pixels
    /// outside the top-left steps, plus one pixel more to the left and above,
    /// in `color`. The view reaches one pixel past the bubble's top and
    /// leading edges; its pixels line up with the bubble's own.
    private func cornerGap(_ color: Color) -> some View {
        Canvas { context, size in
            let p = Self.pixel
            // The bubble's own grid origin, one pixel in from this view's corner.
            let bubbleWidth = size.width - p
            let bubbleBoxHeight = size.height - p - (tailTipX == nil ? 0 : Self.tailHeight)
            let x0 = ((bubbleWidth - CGFloat(max(Int(bubbleWidth / p), 16)) * p) / 2 * 3).rounded(.down) / 3
            let y0 = ((bubbleBoxHeight - CGFloat(max(Int(bubbleBoxHeight / p), 12)) * p) / 2 * 3).rounded(.down) / 3
            // Each part reaches half a pixel further down, under the bubble's
            // outline, so a device-pixel difference in layout rounding never
            // lets a line of what's behind show through.
            var gap = Path()
            gap.addRect(CGRect(x: x0, y: y0, width: 5 * p, height: 3.5 * p))                // row above + first two rows
            gap.addRect(CGRect(x: x0, y: y0 + 3 * p, width: 3 * p, height: 2 * p))          // next two rows
            gap.addRect(CGRect(x: x0 + p, y: y0 + 5 * p, width: 2 * p, height: 0.5 * p))    // under the outline
            context.fill(gap, with: .color(color))
        }
        .padding(.leading, -Self.pixel)
        .padding(.top, -Self.pixel)
    }

    struct GridPoint: Equatable {
        let x: Int, y: Int
    }

    /// The outline's corners, in pixels, clockwise from the top-left: every
    /// segment between two of them is horizontal or vertical. The box is
    /// `columns` × `rows` pixels; the tail's tip is in `tailColumn` (kept
    /// clear of the corners) and reaches four pixels below the box.
    static func outlinePoints(columns w: Int, rows h: Int, tailColumn: Int?) -> [GridPoint] {
        let r = w - 1, b = h - 1
        var points: [(Int, Int)] = [
            (4, 0), (r - 4, 0),                                   // top edge
            (r - 4, 2), (r - 2, 2), (r - 2, 4), (r, 4),           // top-right steps
            (r, b - 4),                                           // right edge
            (r - 2, b - 4), (r - 2, b - 2), (r - 4, b - 2), (r - 4, b), // bottom-right steps
        ]
        if let tip = tailColumn.map({ min(max($0, 10), w - 7) }) {
            // Straight down on the right, two steps back up on the left.
            points += [(tip, b), (tip, b + 4), (tip - 2, b + 4), (tip - 2, b + 2), (tip - 4, b + 2), (tip - 4, b)]
        }
        points += [
            (4, b), (4, b - 2), (2, b - 2), (2, b - 4), (0, b - 4), // bottom-left steps
            (0, 4), (2, 4), (2, 2), (4, 2),                        // left edge, top-left steps
        ]
        return points.map { GridPoint(x: $0.0, y: $0.1) }
    }
}
