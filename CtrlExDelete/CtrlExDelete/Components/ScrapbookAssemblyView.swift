import SwiftUI

/// Ced putting the scrapbook together while the real one is being made:
/// writing on the left page, placing a photo on the right, turning the page,
/// and a little sparkle, looping until the scrapbook is ready. There's no
/// progress number, because there's no honest one to show.
///
/// Ced is the room's pixel artwork (`PixelCedArt`), only moved, never redrawn
/// or reshaped. With Reduce Motion it's one still picture.
struct ScrapbookAssemblyView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One loop: write, place a photo, turn the page, sparkle.
    static let loop: Double = 4.4

    var body: some View {
        Group {
            if reduceMotion {
                scene(time: 2.3)    // a still moment: words written, photo in place
            } else {
                TimelineView(.animation) { timeline in
                    scene(time: timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.loop))
                }
            }
        }
        .frame(width: 300, height: 230)
        .accessibilityElement()
        .accessibilityLabel("Ced is putting your scrapbook together.")
    }

    // MARK: The scene at a moment of the loop

    private func scene(time t: Double) -> some View {
        let writing = progress(t, 0.2, 1.4)        // words appear on the left page
        let placing = progress(t, 1.4, 2.2)        // photo drops onto the right page
        let turning = progress(t, 2.5, 3.4)        // right page turns over
        let sparkle = progress(t, 3.4, 4.2)
        let fadeOut = progress(t, 4.0, 4.4)        // the next loop starts on a fresh page

        // Ced floats to the page he's working on.
        // (Still picture: Ced centred above the finished pages.)
        let cedX: CGFloat = reduceMotion ? 0 : t < 1.4 ? -86 : t < 2.5 ? 92 : t < 3.4 ? 60 : 0
        let bob = reduceMotion ? 0 : sin(t * 2 * .pi / 1.1) * 4

        return ZStack {
            book(writing: writing * (1 - fadeOut), placing: placing * (1 - fadeOut), turning: turning, fadeOut: fadeOut)
                .offset(y: 30)

            // Pencil beside Ced while writing.
            pencil
                .offset(x: cedX + 34, y: -36 + bob)
                .opacity(t < 1.4 ? 1 : 0)

            PixelCedArt()
                .frame(width: 58, height: 78)
                .offset(x: cedX, y: -62 + bob)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: cedX)

            sparkles(sparkle)
        }
    }

    private func progress(_ t: Double, _ start: Double, _ end: Double) -> Double {
        min(max((t - start) / (end - start), 0), 1)
    }

    // MARK: Pieces

    private func book(writing: Double, placing: Double, turning: Double, fadeOut: Double) -> some View {
        let page = RoundedRectangle(cornerRadius: 4)
        return ZStack {
            // Cover peeking out behind the pages (the room scrapbook's rose).
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: 0xB85572))
                .frame(width: 252, height: 128)

            HStack(spacing: 2) {
                // Left page: lines of writing.
                page.fill(Color(hex: 0xFFFBF5))
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(0..<5, id: \.self) { line in
                                let amount = min(max(writing * 5 - Double(line), 0), 1)
                                Capsule()
                                    .fill(CEDColor.accent.opacity(0.55))
                                    .frame(width: (line == 4 ? 50 : 86) * amount, height: 3)
                            }
                        }
                        .padding(14)
                    }
                    .frame(width: 118, height: 116)

                // Right page: a photo settles into place.
                page.fill(Color(hex: 0xFFFBF5))
                    .overlay {
                        photo
                            .rotationEffect(.degrees(-4 + 4 * placing))
                            .scaleEffect(1.25 - 0.25 * placing)
                            .offset(y: -40 * (1 - placing))
                            .opacity(placing)
                    }
                    .frame(width: 118, height: 116)
            }

            // The turning page, folding over from right to left.
            page.fill(Color(hex: 0xF5E8E0))
                .frame(width: 118, height: 116)
                .rotation3DEffect(.degrees(-180 * turning), axis: (x: 0, y: 1, z: 0),
                                  anchor: .leading, perspective: 0.4)
                .offset(x: 60)
                .opacity(turning > 0 && turning < 1 ? 1 : 0)
        }
        .opacity(1 - fadeOut * 0.25)
    }

    private var photo: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                Color(hex: 0x8AB4C8)
                Color(hex: 0x9B7A58).frame(height: 18)
                Circle().fill(Color(hex: 0xFFD878)).frame(width: 9, height: 9)
                    .offset(x: 18, y: -34)
            }
            .frame(width: 70, height: 52)
        }
        .padding(5)
        .padding(.bottom, 6)
        .background(.white)
        .shadow(color: CEDColor.walnut.opacity(0.12), radius: 2, y: 1)
    }

    /// A tiny pixel pencil (not part of Ced).
    private var pencil: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color(hex: 0xE9716D)).frame(width: 5, height: 4)
            Rectangle().fill(Color(hex: 0xEFB073)).frame(width: 5, height: 16)
            Rectangle().fill(Color(hex: 0xF5E8E0)).frame(width: 5, height: 3)
            Rectangle().fill(CEDColor.walnut).frame(width: 2, height: 3)
        }
        .rotationEffect(.degrees(28))
        .accessibilityHidden(true)
    }

    private func sparkles(_ amount: Double) -> some View {
        let points: [(CGFloat, CGFloat, Double)] = [(-110, -10, 0), (112, -24, 0.15), (-60, 96, 0.3), (84, 92, 0.2)]
        return ZStack {
            ForEach(points.indices, id: \.self) { index in
                let (x, y, delay) = points[index]
                let local = min(max((amount - delay) / 0.6, 0), 1)
                CEDIconView(icon: .star, size: 14, color: CEDColor.sunriseAmber)
                    .scaleEffect(sin(local * .pi))
                    .opacity(sin(local * .pi))
                    .offset(x: x, y: y)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    ScrapbookAssemblyView()
        .padding()
        .background(CEDColor.background)
}
