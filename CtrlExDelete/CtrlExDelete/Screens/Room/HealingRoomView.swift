import SwiftUI

/// The healing room: the app's home screen. Tap Ced for today's activity,
/// the scrapbook on the desk for your story, or the telephone to talk instead.
struct HealingRoomView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressedObject: RoomObject?
    @State private var isCedFloating = false

    var body: some View {
        GeometryReader { geometry in
            // Fill the screen like the prototype's `preserveAspectRatio="… slice"`,
            // but keep the top edge in place so the header is never cut off.
            let scale = max(geometry.size.width / RoomGrid.size.width,
                            geometry.size.height / RoomGrid.size.height)
            let roomWidth = RoomGrid.size.width * scale
            let roomHeight = RoomGrid.size.height * scale

            ZStack(alignment: .topLeading) {
                RoomBackdrop()
                    .frame(width: roomWidth, height: roomHeight)
                    .accessibilityElement()
                    .accessibilityLabel("Day 1. Your Healing Room. Ced says: You don\u{2019}t have to feel great today. Let\u{2019}s choose one small thing.")
                    .accessibilityAddTraits(.isHeader)

                cedShadow(scale: scale)
                objectButton(.ced, scale: scale)
                objectButton(.scrapbook, scale: scale)
                objectButton(.phone, scale: scale)

                if let pressedObject {
                    RoomTooltip(text: pressedObject.tooltip)
                        .position(x: pressedObject.tooltipCenter.x * scale,
                                  y: pressedObject.tooltipCenter.y * scale)
                }
            }
            .frame(width: roomWidth, height: roomHeight, alignment: .topLeading)
            .offset(x: (geometry.size.width - roomWidth) / 2)
        }
        .clipped()
        .background(Color(hex: 0x7A4E24), ignoresSafeAreaEdges: [])
        // Let the header's teal run up behind the status bar. The room covers
        // the rest of this color, so it only shows behind the status bar.
        .background(Color(hex: 0x2D5A70), ignoresSafeAreaEdges: .top)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                isCedFloating = true
            }
        }
    }

    // MARK: Tappable objects

    private func objectButton(_ object: RoomObject, scale: CGFloat) -> some View {
        let frame = object.frame
        return Button {
            router.go(to: object.destination)
        } label: {
            object.artwork
                .frame(width: frame.width * scale, height: frame.height * scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(RoomObjectButtonStyle(object: object, pressedObject: $pressedObject))
        // Ced gently floats up and down; his shadow stays on the floor.
        .offset(y: object == .ced && isCedFloating ? -4 * scale : 0)
        .offset(x: frame.minX * scale, y: frame.minY * scale)
        .accessibilityLabel(object.tooltip)
    }

    /// Ced's shadow: stays put and fades a little while he rises.
    private func cedShadow(scale: CGFloat) -> some View {
        Ellipse()
            .fill(CEDColor.walnut)
            .opacity(isCedFloating ? 0.07 : 0.12)
            .frame(width: 40 * scale, height: 10 * scale)
            .offset(x: 175 * scale, y: 511 * scale)
            .accessibilityHidden(true)
    }
}

// MARK: - The three objects

private enum RoomObject {
    case ced, scrapbook, phone

    var destination: AppScreen {
        switch self {
        case .ced: .activities
        case .scrapbook: .scrapbook
        case .phone: .talk
        }
    }

    /// Wording from the prototype's hover tooltips.
    var tooltip: String {
        switch self {
        case .ced: "View Today\u{2019}s Activity"
        case .scrapbook: "Open Scrapbook"
        case .phone: "Talk Instead"
        }
    }

    /// Where the object sits on the 390 × 700 room grid.
    var frame: CGRect {
        switch self {
        case .ced: CGRect(x: 160, y: 428, width: 70, height: 82)
        case .scrapbook: CGRect(x: 50, y: 480, width: 84, height: 46)
        case .phone: CGRect(x: 247, y: 469, width: 75, height: 55)
        }
    }

    /// Tooltip centers from the prototype (it used percentages of the room).
    var tooltipCenter: CGPoint {
        switch self {
        case .ced: CGPoint(x: 390 * 0.62, y: 700 * 0.62)
        case .scrapbook: CGPoint(x: 390 * 0.25, y: 700 * 0.68)
        case .phone: CGPoint(x: 390 * 0.73, y: 700 * 0.64)
        }
    }

    @ViewBuilder var artwork: some View {
        switch self {
        case .ced:
            PixelCedArt()
        case .scrapbook:
            PixelScrapbookArt()
        case .phone:
            // The prototype mutes the phone with saturate(0.7) brightness(0.87).
            Image("phone-clear")
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .saturation(0.7)
                .colorMultiply(Color(white: 0.87))
        }
    }
}

/// While an object is pressed it glows white and its tooltip appears
/// (the prototype shows these on mouse hover, which phones don't have).
private struct RoomObjectButtonStyle: ButtonStyle {
    let object: RoomObject
    @Binding var pressedObject: RoomObject?

    func makeBody(configuration: Configuration) -> some View {
        let glow = configuration.isPressed ? Color.white : .clear
        configuration.label
            .shadow(color: glow, radius: 2)
            .shadow(color: glow.opacity(0.55), radius: 4.5)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    pressedObject = object
                } else if pressedObject == object {
                    pressedObject = nil
                }
            }
    }
}

private struct RoomTooltip: View {
    let text: String

    var body: some View {
        Text(text)
            .cedTextStyle(.captionBold)
            .foregroundStyle(Color(hex: 0xFFF8F0))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(CEDColor.walnut, in: Capsule())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#Preview {
    let _ = FontRegistrar.registerBundledFonts()
    VStack(spacing: 0) {
        HealingRoomView()
        BottomNavBar()
    }
    .environment(AppRouter(start: .room))
}
