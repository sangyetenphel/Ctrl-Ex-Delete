import SwiftUI

// The pixel-art healing room, redrawn from the `PixelRoom` SVG in
// CED-Figma-Reference/src/App.tsx. Every number below is a coordinate on the
// prototype's 390 × 700 grid; HealingRoomView scales the grid to the screen.

enum RoomGrid {
    static let size = CGSize(width: 390, height: 700)
}

/// Colours shared by the room and screens that should feel like part of it
/// (the Grow with Kindness game uses the wall, message card and wood).
enum RoomPalette {
    /// The wall's top-to-bottom gradient and its faint dot texture.
    static let wallStops: [(Double, UInt32)] = [(0, 0x90B8CC), (0.3, 0x9DC0D0), (0.7, 0xA5C5D4), (1, 0xA9C9D8)]
    static let wallDot: UInt32 = 0x7AAFC7
    static let wallDotOpacity = 0.18
    /// Ced's message card: cream fill, pale tan frame, warm brown text.
    static let cardFill: UInt32 = 0xFFF8F0
    static let cardFrame: UInt32 = 0xE0C9B8
    static let cardText: UInt32 = 0x3D2B1F
    static let cardSignature: UInt32 = 0x9E8070
    /// Shelf and desk wood.
    static let woodLight: UInt32 = 0xB07845
    static let wood: UInt32 = 0x9B6A3B
    static let woodDark: UInt32 = 0x7A4E24
}

// MARK: - Drawing helpers

private extension GraphicsContext {
    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ hex: UInt32, opacity: Double = 1) {
        fill(Path(CGRect(x: x, y: y, width: width, height: height)), with: .color(Color(hex: hex, opacity: opacity)))
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ shading: Shading) {
        fill(Path(CGRect(x: x, y: y, width: width, height: height)), with: shading)
    }

    func polygon(_ points: [CGPoint], _ hex: UInt32, opacity: Double) {
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        fill(path, with: .color(Color(hex: hex, opacity: opacity)))
    }

    /// Draws text so that `baseline` is where the text sits, like SVG `<text y="…">`.
    func text(_ string: String, font: CEDFontName, size: CGFloat, hex: UInt32, x: CGFloat, baseline: CGFloat,
              anchor: UnitPoint = .topLeading, tracking: CGFloat = 0) {
        let ascent = FontMetrics.ascender(of: font, size: size)
        let label = Text(string)
            .font(.custom(font.rawValue, fixedSize: size))
            .tracking(tracking)
            .foregroundStyle(Color(hex: hex))
        draw(label, at: CGPoint(x: x, y: baseline - ascent), anchor: anchor)
    }
}

/// A vertical gradient from the top to the bottom of `rect`.
private func verticalGradient(_ stops: [(Double, UInt32)], in rect: CGRect) -> GraphicsContext.Shading {
    .linearGradient(
        Gradient(stops: stops.map { Gradient.Stop(color: Color(hex: $0.1), location: $0.0) }),
        startPoint: CGPoint(x: rect.midX, y: rect.minY),
        endPoint: CGPoint(x: rect.midX, y: rect.maxY)
    )
}

// MARK: - The room (everything that isn't tappable)

struct RoomBackdrop: View {
    /// Shown as "DAY N" in the header.
    var day = 1

    var body: some View {
        Canvas { context, size in
            let scale = size.width / RoomGrid.size.width
            context.scaleBy(x: scale, y: scale)
            Self.drawWallAndFloor(in: context)
            Self.drawHeader(in: context, day: day)
            Self.drawLampAndBookshelf(in: context)
            Self.drawWindowAndPainting(in: context)
            // The big plant is its own tappable object (PixelRoomPlantArt).
            // Ced's speech bubble is drawn on top in SwiftUI (PixelBubble).
            Self.drawDesk(in: context)
        }
        .aspectRatio(RoomGrid.size, contentMode: .fit)
    }

    private static func drawWallAndFloor(in c: GraphicsContext) {
        // Wall  (y 0–556)
        let wall = CGRect(x: 0, y: 0, width: 390, height: 556)
        c.rect(0, 0, 390, 556, verticalGradient(RoomPalette.wallStops, in: wall))
        for x in [35, 75, 150, 230, 310, 360] as [CGFloat] {
            for y in [130, 200, 280, 370, 460] as [CGFloat] {
                c.rect(x, y, 3, 3, RoomPalette.wallDot, opacity: RoomPalette.wallDotOpacity)
            }
        }

        // Floor (y 556–700), baseboard, planks and seams
        let floor = CGRect(x: 0, y: 556, width: 390, height: 144)
        c.rect(0, 556, 390, 144, verticalGradient([(0, 0x9B6235), (1, 0x7A4E24)], in: floor))
        c.rect(0, 552, 390, 7, 0x5C3A1A)
        c.rect(0, 552, 390, 2, 0x4A2A0A)
        for y in [572, 592, 612, 634, 656, 678] as [CGFloat] {
            c.rect(0, y, 390, 2, 0x6B4226, opacity: 0.55)
        }
        for x in [70, 155, 240, 315] as [CGFloat] {
            c.rect(x, 556, 2, 144, 0x6B4226, opacity: 0.28)
        }
    }

    private static func drawHeader(in c: GraphicsContext, day: Int) {
        let header = CGRect(x: 0, y: 0, width: 390, height: 78)
        c.rect(0, 0, 390, 78, verticalGradient([(0, 0x2D5A70), (1, 0x35677D)], in: header))
        c.rect(0, 76, 390, 3, 0x1E4A5E, opacity: 0.7)
        c.text("DAY \(day)", font: .nunitoExtraBold, size: 10, hex: 0xE7F1F6, x: 22, baseline: 28, tracking: 1.8)
        c.text("Your Healing Room", font: .loraBold, size: 20, hex: 0xFFFFFF, x: 22, baseline: 56)
    }

    private static func drawLampAndBookshelf(in c: GraphicsContext) {
        // Ceiling lamp
        c.rect(191, 92, 8, 6, 0x5C3A1A)
        c.rect(174, 96, 42, 24, 0xD9A050)
        c.rect(176, 98, 38, 20, 0xFFD080, opacity: 0.65)
        c.fill(Path(ellipseIn: CGRect(x: 155, y: 108, width: 80, height: 28)), with: .color(Color(hex: 0xFFD060, opacity: 0.16)))

        // Bookshelf: warm wooden backing first, so the wall doesn't show through.
        drawShelfBacking(in: c)
        c.rect(6, 92, 5, 328, 0x7A4E24)
        c.rect(111, 92, 5, 328, 0x7A4E24)
        for y in [92, 172, 252, 332, 416] as [CGFloat] {
            c.rect(6, y, 110, 6, 0x9B6A3B)
            c.rect(6, y + 5, 110, 1, 0x7A4E24, opacity: 0.6)      // the board's lower edge
        }
        drawShelfDecorations(in: c)
        // The books are the user's own (RoomBookshelf, on top), beside these.
    }

    /// Light oak planks inside the frame, with a soft shadow under each
    /// board and along the sides for depth.
    private static func drawShelfBacking(in c: GraphicsContext) {
        c.rect(11, 98, 100, 318, 0xC79E74)
        for x in [36, 61, 86] as [CGFloat] {                    // plank seams
            c.rect(x, 98, 1, 318, 0xB48A61, opacity: 0.8)
        }
        for x in [23, 48, 73, 98] as [CGFloat] {                // a little grain
            for y in [118, 150, 196, 230, 274, 306, 356, 388] as [CGFloat] {
                c.rect(x, y + (x == 48 || x == 98 ? 9 : 0), 6, 1, 0xB48A61, opacity: 0.45)
            }
        }
        for y in [98, 178, 258, 338] as [CGFloat] {              // shadow under each board
            c.rect(11, y, 100, 4, 0x6E4524, opacity: 0.28)
            c.rect(11, y + 4, 100, 2, 0x6E4524, opacity: 0.12)
        }
        c.rect(11, 98, 3, 318, 0x6E4524, opacity: 0.18)          // inner sides
        c.rect(108, 98, 3, 318, 0x6E4524, opacity: 0.18)
    }

    /// One small keepsake per shelf, in a nook RoomBookshelf leaves free
    /// (right, left, right, left). Each stands on its shelf.
    private static func drawShelfDecorations(in c: GraphicsContext) {
        // Top shelf, right: a tiny potted plant.
        c.rect(97, 165, 10, 7, 0xB5603A)                         // pot
        c.rect(96, 164, 12, 2, 0xC4704A)
        c.rect(98, 166, 2, 5, 0xD08060, opacity: 0.6)
        c.rect(101, 151, 2, 13, 0x4E8A3A)                        // stem and leaves
        c.rect(97, 155, 4, 3, 0x6BA84A)
        c.rect(103, 152, 4, 3, 0x6BA84A)
        c.rect(98, 158, 3, 2, 0x4E8A3A)
        c.rect(103, 157, 3, 3, 0x4E8A3A)
        c.rect(100, 148, 3, 3, 0x7BC05A)

        // Second shelf, left: an unlit candle on a little brass holder.
        c.rect(15, 249, 12, 3, 0xC9A050)
        c.rect(17, 247, 8, 2, 0xD9B060)
        c.rect(18, 232, 6, 15, 0xF5E8D0)
        c.rect(18, 232, 2, 15, 0xFFF6E6, opacity: 0.8)
        c.rect(23, 234, 1, 13, 0xE2D2B6)
        c.rect(20, 229, 2, 3, 0x3D2B1F)                          // wick

        // Third shelf, right: a small framed heart.
        c.rect(94, 314, 14, 18, 0x7A4E24)                        // frame
        c.rect(96, 316, 10, 14, 0xFFF4E8)
        for (x, y, w) in [(97, 319, 3), (101, 319, 3), (97, 320, 7), (97, 321, 7), (98, 322, 5), (99, 323, 3), (100, 324, 1)] as [(CGFloat, CGFloat, CGFloat)] {
            c.rect(x, y, w, 1, 0xE9716D)
        }
        c.rect(108, 318, 2, 14, 0x5C3A1A, opacity: 0.5)          // its stand

        // Bottom shelf, left: a tiny Ced figurine (Ced's own colours).
        let ced: UInt32 = 0xF0EEFF
        c.rect(17, 402, 10, 12, ced)
        c.rect(18, 399, 8, 3, ced)
        c.rect(19, 397, 6, 2, ced)
        c.rect(17, 414, 3, 2, ced)
        c.rect(21, 414, 2, 2, ced)
        c.rect(24, 414, 3, 2, ced)
        c.rect(19, 403, 2, 2, 0x3D2B1F)                          // eyes
        c.rect(23, 403, 2, 2, 0x3D2B1F)
        c.rect(18, 405, 2, 1, 0xF09090, opacity: 0.6)            // cheeks
        c.rect(24, 405, 2, 1, 0xF09090, opacity: 0.6)
        c.rect(20, 407, 4, 1, 0x3D2B1F)                          // smile
        c.rect(15, 415, 14, 1, 0x6E4524, opacity: 0.25)          // its shadow
    }

    private static func drawWindowAndPainting(in c: GraphicsContext) {
        // Warm glow around the window (an oval radial gradient)
        var glow = c
        glow.translateBy(x: 200, y: 210)
        glow.scaleBy(x: 1, y: 106.0 / 118.0)
        glow.fill(
            Path(ellipseIn: CGRect(x: -118, y: -118, width: 236, height: 236)),
            with: .radialGradient(
                Gradient(colors: [Color(hex: 0xFFB840, opacity: 0.45), Color(hex: 0xFFB840, opacity: 0)]),
                center: .zero, startRadius: 0, endRadius: 118
            )
        )

        // Window frame, sunset and panes
        c.rect(120, 92, 160, 249, 0x6B4226)
        let sky = CGRect(x: 124, y: 96, width: 152, height: 241)
        c.rect(124, 96, 152, 241, verticalGradient(
            [(0, 0xFF3A10), (0.2, 0xFF6820), (0.5, 0xFFA030), (0.78, 0xFFD060), (1, 0xFFE8A0)], in: sky))
        c.rect(199, 96, 5, 241, 0x6B4226)
        c.rect(124, 211, 152, 5, 0x6B4226)
        c.rect(142, 120, 40, 40, 0xFFE060, opacity: 0.95)
        c.rect(138, 124, 48, 32, 0xFFE060, opacity: 0.5)
        c.rect(134, 128, 56, 24, 0xFFE060, opacity: 0.22)
        c.rect(124, 96, 70, 16, 0xFF3010, opacity: 0.3)
        c.rect(124, 112, 70, 14, 0xFF5820, opacity: 0.2)
        // Sill
        c.rect(114, 337, 172, 12, 0x8B5A2B)
        c.rect(114, 343, 172, 5, 0x9B6A3B)
        // The wall gap between the bookshelf and the window stays open down
        // through the sill's left end, so it meets the top-left corner of
        // Ced's speech bubble as wall instead of brown.
        c.rect(116, 337, 4, 12, verticalGradient(RoomPalette.wallStops, in: CGRect(x: 0, y: 0, width: 390, height: 556)))

        // Wall painting
        c.rect(296, 96, 90, 84, 0x8B5A2B)
        c.rect(300, 100, 82, 76, 0xF5E6D6)
        c.rect(300, 100, 82, 30, 0x7BB8C4, opacity: 0.45)
        c.polygon([CGPoint(x: 306, y: 176), CGPoint(x: 330, y: 126), CGPoint(x: 354, y: 176)], 0xC4633B, opacity: 0.55)
        c.polygon([CGPoint(x: 324, y: 176), CGPoint(x: 350, y: 138), CGPoint(x: 376, y: 176)], 0xD4847A, opacity: 0.52)
        c.rect(330, 106, 18, 18, 0xFFE060, opacity: 0.75)
    }

    /// Ced's speech bubble on the room grid: its outer edge (the text sits
    /// inside, at RoomCedMessage.frame) and where its tail points, just left
    /// of Ced's head so it never covers his face.
    static let speechBubbleFrame = CGRect(x: 112, y: 338, width: 200, height: 81)
    static let speechBubbleTailTipX: CGFloat = 162

    private static func drawDesk(in c: GraphicsContext) {
        c.rect(36, 524, 318, 32, 0x9B6235)
        c.rect(36, 524, 318, 6, 0xB07845)
        c.rect(36, 550, 318, 4, 0x7A4E24)
        // Legs
        c.rect(44, 556, 12, 24, 0x7A4E24)
        c.rect(334, 556, 12, 24, 0x7A4E24)
        c.rect(190, 556, 10, 18, 0x7A4E24)
    }
}

// MARK: - Ced (pixel version)

/// Ced as he appears in the room. Drawn on a 70 × 94 grid whose top-left
/// corner sits at (160, 428) in the room.
struct PixelCedArt: View {
    var body: some View {
        Canvas { c, size in
            let scale = size.width / 70
            c.scaleBy(x: scale, y: scale)
            let body: UInt32 = 0xF0EEFF
            c.rect(10, 36, 50, 34, body)
            c.rect(14, 10, 42, 32, body)
            c.rect(18, 6, 34, 10, body)
            c.rect(22, 2, 26, 8, body)
            c.rect(26, 0, 18, 6, body)

            var hem = Path()
            hem.move(to: CGPoint(x: 10, y: 70))
            hem.addQuadCurve(to: CGPoint(x: 22, y: 70), control: CGPoint(x: 16, y: 82))
            hem.addQuadCurve(to: CGPoint(x: 34, y: 70), control: CGPoint(x: 28, y: 58))
            hem.addQuadCurve(to: CGPoint(x: 46, y: 70), control: CGPoint(x: 40, y: 82))
            hem.addQuadCurve(to: CGPoint(x: 58, y: 70), control: CGPoint(x: 52, y: 58))
            hem.addLine(to: CGPoint(x: 58, y: 66))
            hem.addLine(to: CGPoint(x: 10, y: 66))
            hem.closeSubpath()
            c.fill(hem, with: .color(Color(hex: body)))

            // Eyes, sparkles, cheeks and smile
            c.rect(20, 28, 10, 12, 0x3D2B1F)
            c.rect(40, 28, 10, 12, 0x3D2B1F)
            c.rect(22, 26, 4, 4, 0xFFFFFF)
            c.rect(42, 26, 4, 4, 0xFFFFFF)
            c.rect(12, 38, 10, 6, 0xF09090, opacity: 0.45)
            c.rect(48, 38, 10, 6, 0xF09090, opacity: 0.45)
            c.rect(24, 48, 4, 4, 0x3D2B1F)
            c.rect(28, 52, 14, 4, 0x3D2B1F)
            c.rect(42, 48, 4, 4, 0x3D2B1F)
        }
    }
}

// MARK: - Scrapbook (closed photo album on the desk)

/// Drawn on an 84 × 46 grid whose top-left corner sits at (50, 480) in the room.
struct PixelScrapbookArt: View {
    var body: some View {
        Canvas { c, size in
            let scale = size.width / 84
            c.scaleBy(x: scale, y: scale)
            c.translateBy(x: -50, y: -480) // so the numbers match the prototype

            // Page block
            c.rect(128, 482, 6, 44, 0xF5E8E0)
            c.rect(126, 484, 4, 40, 0xEED8CE)
            c.rect(124, 486, 4, 36, 0xE8CEC4)
            // Cover, face and spine
            c.rect(50, 480, 76, 44, 0xB85572)
            c.rect(63, 482, 62, 40, 0xC46480)
            c.rect(50, 480, 14, 44, 0x6B2848)
            c.rect(52, 482, 4, 40, 0x8A3860, opacity: 0.6)
            // Corner squares
            for (x, y) in [(65, 484), (118, 484), (65, 517), (118, 517)] as [(CGFloat, CGFloat)] {
                c.rect(x, y, 5, 5, 0xE8A0B0)
            }
            // Corner lines
            let lines: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (70, 484, 6, 2), (65, 489, 2, 6), (112, 484, 6, 2), (121, 489, 2, 6),
                (70, 519, 6, 2), (65, 512, 2, 6), (112, 519, 6, 2), (121, 512, 2, 6),
            ]
            for (x, y, width, height) in lines {
                c.rect(x, y, width, height, 0xE8A0B0, opacity: 0.7)
            }
            // Little photo frame with a landscape
            c.rect(82, 495, 24, 18, 0xE8A0B0)
            c.rect(85, 498, 18, 12, 0xC46480)
            c.rect(83, 496, 22, 2, 0xF0B8C4, opacity: 0.7)
            c.rect(83, 496, 2, 16, 0xF0B8C4, opacity: 0.7)
            c.rect(85, 498, 18, 6, 0x8AB4C8)
            c.rect(85, 504, 18, 6, 0x9B7A58)
            c.rect(99, 499, 2, 2, 0xFFD878)
            // Binding dots
            c.rect(55, 496, 4, 4, 0x5A2040)
            c.rect(55, 506, 4, 4, 0x5A2040)
        }
    }
}


// MARK: - The big plant (opens "Grow with Kindness")

extension RoomBackdrop {
    fileprivate static func drawPlant(in c: GraphicsContext) {
        // Pot (sits on the floor line at y = 556)
        c.rect(324, 514, 52, 42, 0xA05228)
        c.rect(320, 509, 60, 10, 0xB8622E)
        c.rect(328, 519, 44, 10, 0x7A3E1A)
        // Stem and leaves
        c.rect(348, 400, 5, 114, 0x5A8A3A)
        let leaves: [(CGFloat, CGFloat, CGFloat, CGFloat, UInt32)] = [
            (319, 400, 32, 18, 0x6BA84A), (314, 406, 22, 12, 0x5A9A3A), (354, 382, 32, 18, 0x5A9A3A),
            (357, 388, 20, 14, 0x7BBF5A), (330, 362, 28, 18, 0x7BBF5A), (333, 368, 18, 12, 0x6BA84A),
            (350, 420, 24, 16, 0x6BA84A), (322, 434, 22, 14, 0x5A9A3A), (338, 450, 18, 12, 0x6BA84A),
            (336, 342, 22, 18, 0x7BBF5A), (338, 348, 14, 12, 0x5A9A3A), (354, 326, 20, 16, 0x6BA84A),
        ]
        for (x, y, width, height, color) in leaves {
            c.rect(x, y, width, height, color)
        }
    }
}

/// The room's big potted plant, exactly as it was drawn in the backdrop, now
/// on its own so it can be tapped and glow like the scrapbook and phone.
/// Drawn on a 76 × 234 grid whose top-left sits at (312, 322) in the room.
/// The desk overlaps the pot's lower-left corner, so that area is cleared:
/// the desk (in the backdrop) stays in front, as before.
struct PixelRoomPlantArt: View {
    static let frame = CGRect(x: 312, y: 322, width: 76, height: 234)

    var body: some View {
        Canvas { c, size in
            c.scaleBy(x: size.width / Self.frame.width, y: size.width / Self.frame.width)
            c.translateBy(x: -Self.frame.minX, y: -Self.frame.minY)
            RoomBackdrop.drawPlant(in: c)
            c.blendMode = .clear
            c.fill(Path(CGRect(x: 312, y: 524, width: 42, height: 32)), with: .color(.black))   // the desk's corner
        }
    }
}


// MARK: - Room pieces for other screens

/// The room's blue wall, with its gradient and faint dot texture, to fill a
/// whole screen (the dots repeat at the room's spacing, scaled to the width).
struct RoomWallBackground: View {
    var body: some View {
        Canvas { c, size in
            let rect = CGRect(origin: .zero, size: size)
            c.fill(Path(rect), with: verticalGradient(RoomPalette.wallStops, in: rect))
            let scale = size.width / RoomGrid.size.width
            let dot = 3 * scale
            for x in [35, 75, 150, 230, 310, 360] as [CGFloat] {
                var y: CGFloat = 60
                while y * scale < size.height {
                    c.fill(Path(CGRect(x: x * scale, y: y * scale, width: dot, height: dot)),
                           with: .color(Color(hex: RoomPalette.wallDot, opacity: RoomPalette.wallDotOpacity)))
                    y += 75
                }
            }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// Ced's message card from the room: cream, with the same thin pixel-art
    /// outline as his speech bubble (no tail).
    func roomMessageCard() -> some View {
        self.background(PixelBubble())
    }
}

/// A simple wooden ledge in the room's shelf colours: a lit top edge, the
/// board, a dark lower lip and two small brackets.
struct WoodenLedge: View {
    var body: some View {
        Canvas { c, size in
            let u = size.height / 26
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ hex: UInt32, _ opacity: Double = 1) {
                c.fill(Path(CGRect(x: x, y: y * u, width: w, height: h * u)), with: .color(Color(hex: hex, opacity: opacity)))
            }
            rect(0, 0, size.width, 3, RoomPalette.woodLight)
            rect(0, 3, size.width, 9, RoomPalette.wood)
            rect(0, 12, size.width, 2, RoomPalette.woodDark)
            for x in [size.width * 0.18, size.width * 0.82 - 10 * u] {
                rect(x, 14, 10 * u, 6, RoomPalette.woodDark)
                rect(x + 2 * u, 20, 6 * u, 4, RoomPalette.woodDark, 0.85)
            }
            rect(0, 14, size.width, 2, 0x3D2B1F, 0.12)        // a soft shadow under the board
        }
        .accessibilityHidden(true)
    }
}


/// Ced's message inside the room's cream card: today's words (from the
/// check-in) and his signature, in the card's own type. The card is part of
/// the artwork and doesn't grow, so the text follows the user's text size up
/// to a point and then shrinks to fit; VoiceOver always reads all of it.
struct RoomCedMessage: View {
    let text: String
    let scale: CGFloat

    /// The card's inside on the room grid (inside its 3-unit frame, a little padding).
    static let frame = CGRect(x: 119, y: 343, width: 186, height: 71)

    var body: some View {
        let textScale = min(UIFontMetrics(forTextStyle: .caption1).scaledValue(for: 1), 1.4)
        VStack(spacing: 5 * scale) {
            Text(text)
                .font(.custom(CEDFontName.nunitoSemiBold.rawValue, fixedSize: 10 * scale * textScale))
                .foregroundStyle(Color(hex: RoomPalette.cardText))
                .lineSpacing(2 * scale)
                .lineLimit(4)
                .minimumScaleFactor(0.55)
            Text("\u{2014} Ced, your healing companion")
                .font(.custom(CEDFontName.nunitoRegular.rawValue, fixedSize: 9 * scale * min(textScale, 1.2)))
                .foregroundStyle(Color(hex: RoomPalette.cardSignature))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .multilineTextAlignment(.center)
        .frame(width: Self.frame.width * scale, height: Self.frame.height * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ced says: \(text)")
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: text)
    }
}
