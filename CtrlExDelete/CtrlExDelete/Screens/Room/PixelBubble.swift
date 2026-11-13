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

    var body: some View {
        Canvas { context, size in
            let boxHeight = size.height - (tailTipX == nil ? 0 : Self.tailHeight)
            let (columns, rows, x0, y0) = Self.grid(width: size.width, boxHeight: boxHeight)
            let tipColumn = tailTipX.map { Int((($0 - x0) / Self.pixel).rounded(.down)) }
            let corners = Self.outlinePoints(columns: columns, rows: rows, tailColumn: tipColumn)

            context.fill(Self.silhouette(corners, x0: x0, y0: y0), with: .color(fill))
            for rect in Self.outlineRects(corners, x0: x0, y0: y0) {
                context.fill(Path(rect), with: .color(Self.outline))
            }
        }
        .accessibilityHidden(true)
    }

    /// The grid a card of this size is drawn on: its columns and rows, and
    /// where pixel (0, 0) starts (the leftover points split evenly on each
    /// side, rounded to whole device pixels).
    static func grid(width: CGFloat, boxHeight: CGFloat) -> (columns: Int, rows: Int, x0: CGFloat, y0: CGFloat) {
        let columns = max(Int(width / pixel), 16), rows = max(Int(boxHeight / pixel), 12)
        let x0 = ((width - CGFloat(columns) * pixel) / 2 * 3).rounded(.down) / 3
        let y0 = ((boxHeight - CGFloat(rows) * pixel) / 2 * 3).rounded(.down) / 3
        return (columns, rows, x0, y0)
    }

    /// The solid stepped shape the outline encloses, outline included.
    static func silhouette(_ corners: [GridPoint], x0: CGFloat, y0: CGFloat) -> Path {
        let p = pixel
        var path = Path()
        path.addLines(corners.map { CGPoint(x: x0 + (CGFloat($0.x) + 0.5) * p, y: y0 + (CGFloat($0.y) + 0.5) * p) })
        path.closeSubpath()
        for rect in outlineRects(corners, x0: x0, y0: y0) { path.addRect(rect) }
        return path
    }

    /// Each straight segment of the outline as a row or column of whole pixels.
    static func outlineRects(_ corners: [GridPoint], x0: CGFloat, y0: CGFloat) -> [CGRect] {
        let p = pixel
        var rects: [CGRect] = []
        for (index, a) in corners.enumerated() {
            let b = corners[(index + 1) % corners.count]
            let x = x0 + CGFloat(min(a.x, b.x)) * p
            let y = y0 + CGFloat(min(a.y, b.y)) * p
            let width = CGFloat(abs(a.x - b.x) + 1) * p
            let height = CGFloat(abs(a.y - b.y) + 1) * p
            rects.append(CGRect(x: x, y: y, width: width, height: height))
        }
        return rects
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

/// A narrow band of wall behind a pixel bubble: the bubble's own stepped
/// silhouette grown by `gap` pixels on every side, painted with the room's
/// wall gradient, so where the bubble sits on the window frame or the
/// bookshelf their outlines don't touch. Over the open wall it's invisible.
/// Its frame is the bubble's box (without the tail) grown by `gap` pixels
/// on every side; `wallTop`/`wallBottom` are where the wall starts and ends,
/// in points from this view's top, so the gradient lines up with the room.
struct PixelBubbleHalo: View {
    var gap = 2
    var wallTop: CGFloat
    var wallBottom: CGFloat

    var body: some View {
        Canvas { context, size in
            let (columns, rows, x0, y0) = PixelBubble.grid(width: size.width, boxHeight: size.height)
            let corners = PixelBubble.outlinePoints(columns: columns, rows: rows, tailColumn: nil)
            let wall = Gradient(stops: RoomPalette.wallStops.map { Gradient.Stop(color: Color(hex: $0.1), location: $0.0) })
            context.fill(PixelBubble.silhouette(corners, x0: x0, y0: y0),
                         with: .linearGradient(wall, startPoint: CGPoint(x: 0, y: wallTop),
                                               endPoint: CGPoint(x: 0, y: wallBottom)))
        }
        .accessibilityHidden(true)
    }
}
