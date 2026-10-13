import SwiftUI

// The pixel-art healing room, redrawn from the `PixelRoom` SVG in
// CED-Figma-Reference/src/App.tsx. Every number below is a coordinate on the
// prototype's 390 × 700 grid; HealingRoomView scales the grid to the screen.

enum RoomGrid {
    static let size = CGSize(width: 390, height: 700)
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
    var body: some View {
        Canvas { context, size in
            let scale = size.width / RoomGrid.size.width
            context.scaleBy(x: scale, y: scale)
            Self.drawWallAndFloor(in: context)
            Self.drawHeader(in: context)
            Self.drawLampAndBookshelf(in: context)
            Self.drawWindowAndPainting(in: context)
            Self.drawPlant(in: context)
            Self.drawSpeechBubble(in: context)
            Self.drawDesk(in: context)
        }
        .aspectRatio(RoomGrid.size, contentMode: .fit)
    }

    private static func drawWallAndFloor(in c: GraphicsContext) {
        // Wall  (y 0–556)
        let wall = CGRect(x: 0, y: 0, width: 390, height: 556)
        c.rect(0, 0, 390, 556, verticalGradient([(0, 0x90B8CC), (0.3, 0x9DC0D0), (0.7, 0xA5C5D4), (1, 0xA9C9D8)], in: wall))
        for x in [35, 75, 150, 230, 310, 360] as [CGFloat] {
            for y in [130, 200, 280, 370, 460] as [CGFloat] {
                c.rect(x, y, 3, 3, 0x7AAFC7, opacity: 0.18)
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

    private static func drawHeader(in c: GraphicsContext) {
        let header = CGRect(x: 0, y: 0, width: 390, height: 78)
        c.rect(0, 0, 390, 78, verticalGradient([(0, 0x2D5A70), (1, 0x35677D)], in: header))
        c.rect(0, 76, 390, 3, 0x1E4A5E, opacity: 0.7)
        c.text("DAY 1", font: .nunitoExtraBold, size: 10, hex: 0xE7F1F6, x: 22, baseline: 28, tracking: 1.8)
        c.text("Your Healing Room", font: .loraBold, size: 20, hex: 0xFFFFFF, x: 22, baseline: 56)
    }

    private static func drawLampAndBookshelf(in c: GraphicsContext) {
        // Ceiling lamp
        c.rect(191, 92, 8, 6, 0x5C3A1A)
        c.rect(174, 96, 42, 24, 0xD9A050)
        c.rect(176, 98, 38, 20, 0xFFD080, opacity: 0.65)
        c.fill(Path(ellipseIn: CGRect(x: 155, y: 108, width: 80, height: 28)), with: .color(Color(hex: 0xFFD060, opacity: 0.16)))

        // Bookshelf frame and shelves
        c.rect(6, 92, 5, 328, 0x7A4E24)
        c.rect(111, 92, 5, 328, 0x7A4E24)
        for y in [92, 172, 252, 332, 416] as [CGFloat] {
            c.rect(6, y, 110, 6, 0x9B6A3B)
        }

        // Books: (x, width, height, color), standing on each shelf
        let shelves: [(shelfY: CGFloat, books: [(CGFloat, CGFloat, CGFloat, UInt32)])] = [
            (172, [(12, 11, 68, 0xC4633B), (25, 9, 60, 0x7B5E7B), (36, 13, 72, 0xD4847A), (51, 10, 64, 0x6BA84A),
                   (63, 12, 70, 0x4A7C9E), (77, 10, 62, 0xE8A87C), (89, 11, 68, 0x9E8070)]),
            (252, [(12, 10, 66, 0x7B5E7B), (24, 13, 60, 0xC4633B), (39, 11, 70, 0x4A7C9E), (52, 9, 62, 0x6BA84A),
                   (63, 12, 68, 0xD4847A), (77, 10, 58, 0xE8A87C), (89, 11, 64, 0x9E8070)]),
            (332, [(12, 12, 62, 0xD4847A), (26, 10, 70, 0xC4633B), (38, 11, 60, 0x9E8070), (51, 13, 72, 0x7B5E7B),
                   (66, 9, 64, 0x4A7C9E), (77, 12, 66, 0x6BA84A)]),
            (416, [(12, 11, 66, 0x4A7C9E), (25, 9, 72, 0xC4633B), (36, 12, 62, 0x6BA84A), (50, 10, 68, 0x7B5E7B),
                   (62, 11, 64, 0xE8A87C), (75, 13, 70, 0xD4847A), (90, 11, 60, 0x9E8070)]),
        ]
        for shelf in shelves {
            for (x, width, height, color) in shelf.books {
                c.rect(x, shelf.shelfY - height, width, height, color)
            }
        }
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

        // Wall painting
        c.rect(296, 96, 90, 84, 0x8B5A2B)
        c.rect(300, 100, 82, 76, 0xF5E6D6)
        c.rect(300, 100, 82, 30, 0x7BB8C4, opacity: 0.45)
        c.polygon([CGPoint(x: 306, y: 176), CGPoint(x: 330, y: 126), CGPoint(x: 354, y: 176)], 0xC4633B, opacity: 0.55)
        c.polygon([CGPoint(x: 324, y: 176), CGPoint(x: 350, y: 138), CGPoint(x: 376, y: 176)], 0xD4847A, opacity: 0.52)
        c.rect(330, 106, 18, 18, 0xFFE060, opacity: 0.75)
    }

    private static func drawPlant(in c: GraphicsContext) {
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

    private static func drawSpeechBubble(in c: GraphicsContext) {
        c.rect(112, 340, 200, 78, 0xFFF8F0)
        c.rect(112, 338, 200, 3, 0xE0C9B8)
        c.rect(112, 416, 200, 3, 0xE0C9B8)
        c.rect(112, 338, 3, 81, 0xE0C9B8)
        c.rect(309, 338, 3, 81, 0xE0C9B8)
        c.text("You don\u{2019}t have to feel great today.", font: .nunitoSemiBold, size: 10, hex: 0x3D2B1F,
               x: 212, baseline: 364, anchor: .top)
        c.text("Let\u{2019}s choose one small thing.", font: .nunitoSemiBold, size: 10, hex: 0x3D2B1F,
               x: 212, baseline: 382, anchor: .top)
        c.text("\u{2014} Ced, your healing companion", font: .nunitoRegular, size: 9, hex: 0x9E8070,
               x: 212, baseline: 404, anchor: .top)
    }

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
