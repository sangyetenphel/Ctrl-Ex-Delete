import SwiftUI

/// A cream card with a pixel-art outline, built from square "pixels" the
/// size of the line width (like a sprite, not a stroked shape): each corner
/// is a little rounded staircase, and an optional speech-bubble tail hangs
/// under the bottom edge. Ced's message in the healing room uses the tail;
/// the Grow with Kindness cards use the plain box.
///
///   corner (top-left)        tail (tip on the right)
///   . . . . X X X X          X X X X . . . X X X   ← bottom edge
///   . . X X                        X . . X
///   . X                              X . X
///   . X                                X X
///   X                                    X
///   X
struct PixelBubble: View {
    /// Outline color (a soft taupe-brown, lighter than the room's furniture
    /// outlines), shared by every pixel card.
    static let outline = Color(hex: 0x8B7768)
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
            let p = Self.pixel
            let boxHeight = size.height - (tailTipX == nil ? 0 : Self.tailHeight)
            let columns = max(Int(size.width / p), 12)
            let rows = max(Int(boxHeight / p), 10)
            // The few points left over are split evenly on each side,
            // rounded to whole device pixels.
            let x0 = ((size.width - CGFloat(columns) * p) / 2 * 3).rounded(.down) / 3
            let y0 = ((boxHeight - CGFloat(rows) * p) / 2 * 3).rounded(.down) / 3
            let tipColumn = tailTipX.map { Int((($0 - x0) / p).rounded(.down)) }
            let runs = Self.runs(columns: columns, rows: rows, tailColumn: tipColumn)

            func draw(_ run: Run, _ color: Color) {
                let rect = CGRect(x: x0 + CGFloat(run.column) * p, y: y0 + CGFloat(run.row) * p,
                                  width: CGFloat(run.length) * p, height: p)
                context.fill(Path(rect), with: .color(color))
            }
            runs.fill.forEach { draw($0, fill) }
            runs.outline.forEach { draw($0, Self.outline) }
        }
        .accessibilityHidden(true)
    }

    /// A horizontal run of pixels: `length` pixels from `column` in `row`.
    struct Run: Equatable {
        let row: Int, column: Int, length: Int
    }

    /// The outline and fill pixels for a box `columns` × `rows` pixels, with
    /// the tail's tip in `tailColumn` (kept clear of the corners), or none.
    static func runs(columns w: Int, rows h: Int, tailColumn: Int?) -> (outline: [Run], fill: [Run]) {
        var outline: [Run] = [], fill: [Run] = []
        func line(_ row: Int, _ from: Int, _ to: Int, into list: inout [Run]) {
            if to >= from { list.append(Run(row: row, column: from, length: to - from + 1)) }
        }
        // Rows 0–3 and the last four mirror each other; the sides in between.
        for (offset, outer, inner) in [(0, 4, -1), (1, 2, 4), (2, 1, 2), (3, 1, 2)] {
            for row in Set([offset, h - 1 - offset]) {
                if offset == 0 {
                    if row == h - 1, let tail = tailColumn.map({ min(max($0, 8), w - 6) }) {
                        line(row, 4, tail - 4, into: &outline)      // bottom edge, left of the tail
                        line(row, tail - 3, tail - 1, into: &fill)  // the tail's opening
                        line(row, tail, w - 5, into: &outline)      // right of the tail
                    } else {
                        line(row, 4, w - 5, into: &outline)
                    }
                } else {
                    line(row, outer, inner - 1, into: &outline)
                    line(row, w - inner, w - 1 - outer, into: &outline)
                    line(row, inner, w - 1 - inner, into: &fill)
                }
            }
        }
        for row in 4..<(h - 4) {
            line(row, 0, 0, into: &outline)
            line(row, w - 1, w - 1, into: &outline)
            line(row, 1, w - 2, into: &fill)
        }
        if let tail = tailColumn.map({ min(max($0, 8), w - 6) }) {
            // Straight down on the right; one pixel per row on the left.
            for step in 0..<4 {
                let row = h + step
                line(row, tail - 3 + step, tail - 3 + step, into: &outline)
                line(row, tail - 2 + step, tail - 1, into: &fill)
                if step < 3 { line(row, tail, tail, into: &outline) }
            }
        }
        return (outline, fill)
    }
}
