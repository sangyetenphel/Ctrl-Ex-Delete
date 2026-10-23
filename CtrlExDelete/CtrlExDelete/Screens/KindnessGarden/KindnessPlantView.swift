import SwiftUI

/// The plant in "Grow with Kindness": a pixel-art terracotta pot with soil and
/// a sprout, drawn on a 100 × 130 grid like the room's artwork. The pot and
/// the base of the stem never move; the stem lengthens a little as each leaf
/// grows (right, left, right), and a flower opens at the top at the end.
struct KindnessPlantView: View {
    /// Leaves grown so far (0–3).
    let leaves: Int
    let isBloomed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let grid = CGSize(width: 100, height: 130)
    /// Where the stem leaves the soil (grid), and its height for 0–3 leaves.
    private static let stemBase = CGPoint(x: 50, y: 88)
    private static let stemHeights: [CGFloat] = [12, 30, 48, 64]
    /// Leaf attachment heights above the soil and the side each grows to.
    private static let leafSpots: [(height: CGFloat, side: CGFloat)] = [(16, 1), (33, -1), (50, 1)]

    var body: some View {
        GeometryReader { geometry in
            let unit = min(geometry.size.width / Self.grid.width, geometry.size.height / Self.grid.height)
            let origin = CGPoint(x: (geometry.size.width - Self.grid.width * unit) / 2,
                                 y: geometry.size.height - Self.grid.height * unit)
            let stemHeight = Self.stemHeights[min(leaves, 3)]

            ZStack(alignment: .topLeading) {
                // Stem, growing up from the soil.
                Rectangle()
                    .fill(Color(hex: 0x4E8A3A))
                    .overlay(alignment: .leading) { Rectangle().fill(Color(hex: 0x6BA84A)).frame(width: unit) }
                    .frame(width: 4 * unit, height: stemHeight * unit)
                    .offset(x: origin.x + (Self.stemBase.x - 2) * unit,
                            y: origin.y + (Self.stemBase.y - stemHeight) * unit)
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.6), value: leaves)

                ForEach(0..<3, id: \.self) { index in
                    leaf(index, unit: unit, origin: origin)
                }

                flower(unit: unit, origin: origin, stemHeight: stemHeight)

                Canvas { context, _ in
                    context.translateBy(x: origin.x, y: origin.y)
                    context.scaleBy(x: unit, y: unit)
                    Self.drawPot(in: context)
                }
                .allowsHitTesting(false)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if isBloomed { return "Your plant has three leaves and a flower." }
        switch leaves {
        case 0: return "A small sprout in a pot."
        case 1: return "Your plant has one leaf."
        default: return "Your plant has \(leaves) leaves."
        }
    }

    // MARK: Leaves and flower

    private func leaf(_ index: Int, unit: CGFloat, origin: CGPoint) -> some View {
        let spot = Self.leafSpots[index]
        let isGrown = index < leaves
        let width: CGFloat = 27, height: CGFloat = 15
        // Attached at the stem, growing outwards on its side.
        let attachX = Self.stemBase.x + spot.side * 2
        let x = spot.side > 0 ? attachX : attachX - width
        let y = Self.stemBase.y - spot.height - height / 2

        return PixelLeaf(pointsRight: spot.side > 0)
            .frame(width: width * unit, height: height * unit)
            .scaleEffect(isGrown || reduceMotion ? 1 : 0.05, anchor: spot.side > 0 ? .leading : .trailing)
            .rotationEffect(.degrees(isGrown || reduceMotion ? 0 : spot.side * 25), anchor: spot.side > 0 ? .leading : .trailing)
            .opacity(isGrown ? 1 : 0)
            .offset(x: origin.x + x * unit, y: origin.y + y * unit)
            .animation(reduceMotion ? .easeInOut(duration: 0.3) : .spring(response: 0.7, dampingFraction: 0.65).delay(0.25),
                       value: isGrown)
    }

    private func flower(unit: CGFloat, origin: CGPoint, stemHeight: CGFloat) -> some View {
        let size: CGFloat = 28
        return PixelFlower()
            .frame(width: size * unit, height: size * unit)
            .scaleEffect(isBloomed || reduceMotion ? 1 : 0.1, anchor: .bottom)
            .opacity(isBloomed ? 1 : 0)
            .offset(x: origin.x + (Self.stemBase.x - size / 2) * unit,
                    y: origin.y + (Self.stemBase.y - stemHeight - size + 4) * unit)
            .animation(reduceMotion ? .easeInOut(duration: 0.3) : .spring(response: 0.8, dampingFraction: 0.6).delay(0.9),
                       value: isBloomed)
    }

    // MARK: Pot and soil (never move)

    private static func drawPot(in c: GraphicsContext) {
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ hex: UInt32, _ opacity: Double = 1) {
            c.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(Color(hex: hex, opacity: opacity)))
        }
        // Soil in the pot's mouth.
        rect(20, 86, 60, 6, 0x6B4226)
        for (x, y) in [(26, 87), (36, 89), (47, 87), (58, 89), (68, 87), (31, 90), (63, 90)] as [(CGFloat, CGFloat)] {
            rect(x, y, 3, 1, 0x8A5A30)
        }
        // Rim.
        rect(14, 90, 72, 10, 0xC4704A)
        rect(14, 90, 72, 2, 0xD8885E)
        rect(14, 98, 72, 2, 0x9C5232)
        // Body, narrowing slightly towards the base.
        rect(18, 100, 64, 8, 0xB5603A)
        rect(20, 108, 60, 8, 0xB5603A)
        rect(22, 116, 56, 8, 0xB5603A)
        rect(24, 124, 52, 6, 0xA05228)
        // Light on the left, shade on the right.
        rect(22, 102, 4, 20, 0xD08060, 0.55)
        rect(72, 100, 6, 24, 0x7A3E1A, 0.35)
        // A soft shadow under the pot.
        rect(18, 129, 64, 1, 0x3D2B1F, 0.15)
    }
}

/// A leaf in solid pixel steps, darker along its middle vein.
private struct PixelLeaf: View {
    let pointsRight: Bool

    var body: some View {
        Canvas { c, size in
            let u = size.width / 20
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ hex: UInt32) {
                let left = pointsRight ? x : 20 - x - w
                c.fill(Path(CGRect(x: left * u, y: y * u, width: w * u, height: h * u)), with: .color(Color(hex: hex)))
            }
            rect(0, 4, 4, 3, 0x5A9A3A)
            rect(3, 2, 8, 7, 0x6BA84A)
            rect(10, 1, 6, 9, 0x6BA84A)
            rect(15, 3, 4, 5, 0x6BA84A)
            rect(18, 4, 2, 3, 0x7BBF5A)
            rect(5, 3, 8, 2, 0x7BBF5A)                  // light edge
            rect(2, 5, 16, 1, 0x4E8A3A)                 // vein
        }
    }
}

/// A small pink pixel flower with a golden centre.
private struct PixelFlower: View {
    var body: some View {
        Canvas { c, size in
            let u = size.width / 22
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ hex: UInt32) {
                c.fill(Path(CGRect(x: x * u, y: y * u, width: w * u, height: h * u)), with: .color(Color(hex: hex)))
            }
            let petal: UInt32 = 0xE0729A, light: UInt32 = 0xF29DBA, dark: UInt32 = 0xC4577F
            rect(8, 0, 6, 7, petal)                     // top
            rect(9, 1, 3, 3, light)
            rect(0, 7, 7, 7, petal)                     // left
            rect(1, 8, 3, 3, light)
            rect(15, 7, 7, 7, petal)                    // right
            rect(16, 8, 3, 3, light)
            rect(3, 14, 6, 6, dark)                     // lower petals
            rect(13, 14, 6, 6, dark)
            rect(6, 5, 10, 11, petal)
            rect(8, 7, 6, 6, 0xF2C14E)                  // centre
            rect(9, 8, 2, 2, 0xFFE08A)
        }
    }
}

#Preview {
    VStack {
        KindnessPlantView(leaves: 0, isBloomed: false).frame(height: 220)
        KindnessPlantView(leaves: 3, isBloomed: true).frame(height: 220)
    }
    .background(CEDColor.background)
}
