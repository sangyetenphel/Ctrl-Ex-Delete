import SwiftUI

/// Ced offering the scrapbook: the usual Ced (`GhostView`, unchanged) with
/// the room's pink scrapbook (`PixelScrapbookArt`, the same book shown on
/// the scrapbook's cover) held out in front of him by two small rounded
/// hands, tilted towards the user. He floats gently; with Reduce Motion he
/// stays still. His floor shadow stays on the floor while he floats.
struct CedPresentingGift: View {
    var size: CGFloat = 110
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFloatingUp = false

    // GhostView draws on an 80 × 92 grid in a size × size·1.15 frame,
    // so one grid unit is `unit` points both ways.
    private var unit: CGFloat { size / 80 }
    private var ghostHeight: CGFloat { size * 1.15 }

    var body: some View {
        ZStack(alignment: .top) {
            floorShadow
            ced
                .offset(y: isFloatingUp ? -5 : 0)
        }
        .frame(width: size * 1.1, height: ghostHeight)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                isFloatingUp = true
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Ced holding out a pink scrapbook for you")
    }

    private var ced: some View {
        ZStack(alignment: .top) {
            // Ced without his floor shadow (it's drawn separately below).
            GhostView(size: size)
                .mask(alignment: .top) {
                    Rectangle().frame(height: 83 * unit)   // the shadow starts at y 84
                }

            // The scrapbook, held low in front of him and tipped towards the user.
            ZStack {
                PixelScrapbookArt()
                    .frame(width: 60 * unit, height: 60 * unit * 46 / 84)
                // Under the bottom corners, as if offering it on open palms.
                hand.offset(x: -23 * unit, y: 15 * unit)
                hand.offset(x: 23 * unit, y: 15 * unit)
            }
            .rotationEffect(.degrees(-5))
            .offset(y: 54 * unit)
        }
        .frame(width: size, height: ghostHeight, alignment: .top)
    }

    /// A small rounded ghost hand in Ced's body colour, gripping the book's edge.
    private var hand: some View {
        Ellipse()
            .fill(CEDColor.ghostBody)
            .overlay(Ellipse().strokeBorder(CEDColor.walnut.opacity(0.08), lineWidth: 1))
            .frame(width: 12 * unit, height: 10 * unit)
    }

    /// GhostView's own shadow ellipse (cx 40, cy 88, rx 17, ry 4), kept on the floor.
    private var floorShadow: some View {
        Ellipse()
            .fill(CEDColor.walnut.opacity(0.1))
            .frame(width: 34 * unit * (isFloatingUp ? 0.9 : 1), height: 8 * unit)
            .offset(y: 84 * unit)
    }
}

#Preview {
    CedPresentingGift()
        .padding(40)
        .background(CEDColor.background)
}
