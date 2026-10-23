import SwiftUI

/// The books on the room's bookshelf: one for each completed activity (its
/// reflection was saved), in the order they were completed, coloured by the
/// activity's category. Eight per shelf, left to right, top shelf first; 32 fit.
///
/// Drawn on the room's 390 × 700 grid over RoomBackdrop's decorated shelves, in
/// the same flat pixel style as the room. Each position has a fixed height,
/// so a book looks the same every time. Only a book the user hasn't seen
/// on the shelf yet slides into place; reopening the room replays nothing.
struct RoomBookshelf: View {
    let books: [ShelfBookDTO]
    /// Fresh from the backend (not the on-device copy), so it's safe to
    /// decide which books are new.
    let isCurrent: Bool
    let scale: CGFloat

    static let capacity = 32
    static let perShelf = 8

    /// How many books this phone has already shown on the shelf.
    @AppStorage("roomBookshelfShown") private var shownCount = -1
    /// Books from this index on are arriving now.
    @State private var arrivingFrom: Int?
    @State private var hasArrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Grid positions (see RoomArtwork's bookshelf): the top of each shelf a
    // row of books stands on, and where the first of its eight slots starts.
    // Each shelf keeps a small nook for its keepsake (plant, candle, framed
    // heart, little Ced), right/left/right/left, so books start after it on
    // the left-hand ones and stop before it on the others. Never overlapping.
    private static let shelfTops: [CGFloat] = [172, 252, 332, 416]
    private static let firstX: [CGFloat] = [13, 31, 13, 31]
    private static let gap: CGFloat = 1
    /// Each slot's spine width: a little variety, eight to a shelf, always
    /// 71 units plus 7 gaps, so a full row ends before the keepsake/frame.
    private static let widths: [[CGFloat]] = [
        [9, 8, 10, 9, 8, 10, 9, 8],
        [8, 10, 9, 8, 10, 8, 9, 9],
        [10, 9, 8, 9, 10, 8, 8, 9],
        [9, 10, 8, 8, 9, 10, 9, 8],
    ]
    /// Gentle, fixed heights with room above (rows have 74–78 units).
    private static let heights: [[CGFloat]] = [
        [54, 50, 57, 52, 55, 49, 56, 53],
        [52, 56, 49, 54, 58, 51, 53, 55],
        [50, 55, 53, 57, 49, 54, 56, 52],
        [56, 51, 54, 50, 57, 53, 49, 55],
    ]
    /// Slots whose book may lean, but only into an empty slot beside it.
    private static let leaningSlots: Set<Int> = [1, 3, 4, 6]

    var body: some View {
        let shown = Array(books.prefix(Self.capacity))
        ZStack(alignment: .topLeading) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, book in
                bookView(book, at: index)
            }
        }
        .frame(width: RoomGrid.size.width * scale, height: RoomGrid.size.height * scale, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText(count: shown.count))
        .onAppear(perform: noticeNewBooks)
        .onChange(of: books) { _, _ in noticeNewBooks() }
        .onChange(of: isCurrent) { _, _ in noticeNewBooks() }
    }

    private func bookView(_ book: ShelfBookDTO, at index: Int) -> some View {
        let row = index / Self.perShelf
        let slot = index % Self.perShelf
        let width = Self.widths[row][slot]
        let height = Self.heights[row][slot]
        let x = Self.firstX[row] + Self.widths[row][..<slot].reduce(0, +) + CGFloat(slot) * Self.gap
        let top = Self.shelfTops[row] - height
        let isArriving = arrivingFrom.map { index >= $0 } ?? false
        let isHidden = isArriving && !hasArrived
        // A gentle lean to the right, resting on its bottom corner, only for the
        // last book of a row with an empty slot beside it (so it never touches
        // a neighbour or a keepsake). Straightens once the next book arrives.
        let shownCount = min(books.count, Self.capacity)
        let leans = Self.leaningSlots.contains(slot) && index == shownCount - 1

        return BookSpine(color: Activity.palette(for: book.category).accent, width: width, height: height,
                         style: BookSpine.Style(seed: index), scale: scale)
            .rotationEffect(.degrees(leans ? 4 : 0), anchor: .bottomTrailing)
            // A new book slides down into its place and settles.
            .scaleEffect(x: 1, y: isHidden && !reduceMotion ? 0.4 : 1, anchor: .bottom)
            .offset(y: isHidden && !reduceMotion ? -14 * scale : 0)
            .opacity(isHidden ? 0 : 1)
            .offset(x: x * scale, y: top * scale)
    }

    private func accessibilityText(count: Int) -> String {
        switch count {
        case 0: "Your bookshelf. A book appears here for each activity you complete."
        case 1: "Your bookshelf, with 1 book: one for an activity you completed."
        default: "Your bookshelf, with \(count) books: one for each activity you completed."
        }
    }

    /// Animates only books this phone hasn't shown yet. The first time the
    /// shelf is seen (including after updating the app), the books already
    /// earned are simply there.
    private func noticeNewBooks() {
        guard isCurrent else { return }
        let count = min(books.count, Self.capacity)
        if shownCount < 0 || count < shownCount {
            shownCount = count               // first look, or a reset installation
            return
        }
        guard count > shownCount, arrivingFrom == nil else { return }
        let newBooks = count - shownCount
        arrivingFrom = shownCount
        hasArrived = false
        shownCount = count
        withAnimation(reduceMotion ? .easeIn(duration: 0.4)
                                   : .spring(response: 0.55, dampingFraction: 0.7).delay(0.5)) {
            hasArrived = true
        } completion: {
            arrivingFrom = nil       // settled; ready for the next one
        }
        AccessibilityNotification.Announcement(newBooks == 1 ? "A new book on your shelf." : "New books on your shelf.").post()
    }
}

// MARK: - One book spine

/// A small pixel-art spine in the category colour: a light strip on the left,
/// a darker side edge on the right, binding lines, cream or muted-gold bands
/// near the top and bottom, and on some books a little label panel. Drawn in
/// whole grid units so it stays crisp. `Style(seed:)` fixes the details per
/// shelf position, so a book always looks the same.
struct BookSpine: View {
    struct Style: Equatable {
        let bandColor: Color
        let doubleBands: Bool
        let hasLabel: Bool
        let labelHigh: Bool

        init(seed: Int) {
            bandColor = seed % 3 == 1 ? Color(hex: 0xD9B060) : Color(hex: 0xF1E2C2)   // muted gold or cream
            doubleBands = seed % 4 == 2
            hasLabel = [0, 3, 5].contains(seed % 7)
            labelHigh = seed % 2 == 0
        }
    }

    let color: Color
    let width: CGFloat       // grid units
    let height: CGFloat
    let style: Style
    let scale: CGFloat

    var body: some View {
        Canvas { c, _ in
            c.scaleBy(x: scale, y: scale)
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ fill: Color) {
                c.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(fill))
            }
            let dark = shade(-0.28), light = shade(0.22), binding = shade(-0.18)

            rect(0, 0, width, height, color)
            rect(0, 0, 1, height, light)                       // highlight
            rect(width - 1.5, 0, 1.5, height, dark)            // side edge
            rect(0, 1.5, width, 0.75, binding)                 // binding lines
            rect(0, height - 2.25, width, 0.75, binding)

            // Bands near the top and bottom.
            rect(1, 5, width - 2.5, 1.5, style.bandColor)
            rect(1, height - 7, width - 2.5, 1.5, style.bandColor)
            if style.doubleBands {
                rect(1, 8, width - 2.5, 0.75, style.bandColor)
                rect(1, height - 9.5, width - 2.5, 0.75, style.bandColor)
            }

            // A small label panel with a "title" line on some books.
            if style.hasLabel {
                let labelY = style.labelHigh ? height * 0.3 : height * 0.5
                rect(2, labelY, width - 4, 8, Color(hex: 0xF5EAD2))
                rect(2.5, labelY + 3.5, width - 5, 1, shade(-0.1).opacity(0.8))
            }
        }
        .frame(width: width * scale, height: height * scale)
    }

    /// The category colour, lighter (positive) or darker (negative).
    private func shade(_ amount: CGFloat) -> Color {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func adjust(_ value: CGFloat) -> CGFloat {
            amount >= 0 ? value + (1 - value) * amount : value * (1 + amount)
        }
        return Color(red: adjust(red), green: adjust(green), blue: adjust(blue))
    }
}
