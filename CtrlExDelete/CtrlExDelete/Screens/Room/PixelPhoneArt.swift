import SwiftUI

/// The room's red rotary telephone (opens "Get Support"), drawn in the same
/// simple pixel style as Ced, the scrapbook and the plant: flat blocks on a
/// 3-unit grid, warm muted reds, soft dark brown instead of black.
/// Fills the phone's 75 × 55 room frame (`RoomObject.phone.frame`), like the
/// original artwork ("phone-clear" in the asset catalog, kept for reverting).
struct PixelPhoneArt: View {
    private static let red: UInt32 = 0xB8483F
    private static let redLight: UInt32 = 0xC9604F
    private static let redDark: UInt32 = 0x8F3530
    private static let redDeep: UInt32 = 0x6E2C27
    private static let brown: UInt32 = 0x5A3D33
    private static let dial: UInt32 = 0xDCD3C6
    private static let dialHole: UInt32 = 0xA6998A
    private static let dialCenter: UInt32 = 0x8A7D70

    var body: some View {
        Canvas { c, size in
            let scale = size.width / 75
            c.scaleBy(x: scale, y: scale)
            c.translateBy(x: 0, y: 1)   // 18 rows of 3 = 54 of the 55 units, feet on the bottom

            /// Blocks `col0...col1` in `row` (each block is 3 × 3 units).
            func blocks(_ row: Int, _ col0: Int, _ col1: Int, _ hex: UInt32) {
                let rect = CGRect(x: col0 * 3, y: row * 3, width: (col1 - col0 + 1) * 3, height: 3)
                c.fill(Path(rect), with: .color(Color(hex: hex)))
            }

            // Handset: a long bar with an ear cup hanging at each end.
            blocks(0, 7, 17, Self.redLight)
            blocks(1, 4, 20, Self.red)
            blocks(2, 2, 22, Self.red)
            for row in 3...4 {
                blocks(row, 1, 5, Self.red)
                blocks(row, 19, 23, Self.red)
                blocks(row, 8, 16, Self.redDark)    // the cradle under the handset
            }
            blocks(5, 1, 5, Self.redDark)
            blocks(5, 19, 23, Self.redDark)
            blocks(3, 8, 16, Self.brown)            // soft seam between handset and cradle

            // Body: widens toward the base, lit a little on the left.
            for row in 5...7 { blocks(row, 7, 17, Self.red) }
            for row in 8...11 { blocks(row, 6, 18, Self.red); blocks(row, 6, 6, Self.redLight) }
            for row in 12...14 { blocks(row, 5, 19, Self.red); blocks(row, 5, 5, Self.redLight) }
            blocks(15, 4, 20, Self.redDark)
            blocks(16, 4, 20, Self.redDeep)
            blocks(17, 5, 7, Self.brown)            // feet
            blocks(17, 17, 19, Self.brown)

            // Rotary dial: a stepped circle with six finger holes.
            blocks(6, 10, 14, Self.dial)
            blocks(7, 9, 15, Self.dial)
            for row in 8...11 { blocks(row, 8, 16, Self.dial) }
            blocks(12, 9, 15, Self.dial)
            blocks(13, 10, 14, Self.dial)
            for (col, row) in [(10, 8), (14, 8), (9, 10), (15, 10), (10, 12), (14, 12)] {
                blocks(row, col, col, Self.dialHole)
            }
            for row in 9...10 { blocks(row, 11, 13, Self.dialCenter) }

            // Cord: from the left ear cup down to the base.
            blocks(6, 1, 1, Self.brown)
            for row in 7...12 { blocks(row, 0, 0, Self.brown) }
            blocks(13, 1, 1, Self.brown)
            blocks(14, 2, 2, Self.brown)
            blocks(15, 3, 3, Self.brown)
        }
    }
}
