import SwiftUI

/// The healing room: the app's home screen. Tap Ced for today's activity,
/// the scrapbook on the desk for your story, the telephone to talk instead,
/// or the big plant for "Grow with Kindness".
struct HealingRoomView: View {
    @Environment(AppRouter.self) private var router
    @Environment(JourneyStore.self) private var journey
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressedObject: RoomObject?
    /// Under a pointer (iPad or trackpad): the same glow and tooltip as pressing.
    @State private var hoveredObject: RoomObject?
    @State private var tooltipSize: CGSize = .zero
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
                RoomBackdrop(day: journey.dayNumber)
                    .frame(width: roomWidth, height: roomHeight)
                    .accessibilityElement()
                    .accessibilityLabel("Day \(journey.dayNumber). Your Healing Room.")
                    .accessibilityAddTraits(.isHeader)

                // Ced's speech bubble (pixel outline, tail toward him) and his
                // words for today inside it.
                PixelBubble(tailTipX: (RoomBackdrop.speechBubbleTailTipX - RoomBackdrop.speechBubbleFrame.minX) * scale)
                    .frame(width: RoomBackdrop.speechBubbleFrame.width * scale,
                           height: RoomBackdrop.speechBubbleFrame.height * scale + PixelBubble.tailHeight)
                    .offset(x: RoomBackdrop.speechBubbleFrame.minX * scale, y: RoomBackdrop.speechBubbleFrame.minY * scale)
                roomMessage(scale: scale)
                    .offset(x: RoomCedMessage.frame.minX * scale, y: RoomCedMessage.frame.minY * scale)

                // One book per completed activity, on the empty shelves above.
                RoomBookshelf(books: journey.books, isCurrent: journey.cachedAt == nil && journey.hasLoaded,
                              scale: scale)

                cedShadow(scale: scale)
                objectButton(.ced, scale: scale)
                objectButton(.scrapbook, scale: scale)
                objectButton(.phone, scale: scale)
                objectButton(.plant, scale: scale)

                if let object = pressedObject ?? hoveredObject {
                    // Kept fully on screen: the room can be wider than the
                    // screen (its sides are cropped), and the plant is near the edge.
                    let visibleLeft = -(geometry.size.width - roomWidth) / 2
                    RoomTooltip(text: object.tooltip)
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { tooltipSize = $0 }
                        .position(RoomTooltipLayout.center(for: object, size: tooltipSize, scale: scale,
                                                           visibleLeft: visibleLeft,
                                                           visibleWidth: geometry.size.width))
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
        // Today's message, if the room doesn't have it yet (the check-in and
        // startup usually provide it, so this is rarely a request).
        .task { await journey.loadRoomMessage(today: LocalDate.text()) }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                isCedFloating = true
            }
        }
    }

    // MARK: Ced's card

    /// The card looks the same either way. While Ced invites the user to try
    /// an activity, tapping it opens today's recommendations, like tapping Ced.
    @ViewBuilder
    private func roomMessage(scale: CGFloat) -> some View {
        let line = journey.roomLine(today: LocalDate.text())
        let card = RoomCedMessage(text: line.text, scale: scale)
        if line.isInvitation {
            Button {
                router.go(to: RoomObject.ced.destination)
            } label: {
                card.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ced says: \(line.text)")
            .accessibilityHint("Opens today\u{2019}s activity ideas")
            .accessibilityAddTraits(.isButton)
        } else {
            card
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
        .buttonStyle(RoomObjectButtonStyle(object: object, pressedObject: $pressedObject,
                                           isHovered: hoveredObject == object))
        .onHover { isOver in
            if isOver { hoveredObject = object } else if hoveredObject == object { hoveredObject = nil }
        }
        // Ced gently floats up and down; his shadow stays on the floor.
        .offset(y: object == .ced && isCedFloating ? -4 * scale : 0)
        .offset(x: frame.minX * scale, y: frame.minY * scale)
        .accessibilityLabel(object.tooltip)
        .accessibilityHint(object.accessibilityHint)
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

// MARK: - The objects you can tap

private enum RoomObject {
    case ced, scrapbook, phone, plant

    static let all: [RoomObject] = [.ced, .scrapbook, .phone, .plant]

    var destination: AppScreen {
        switch self {
        case .ced: .activities
        case .scrapbook: .scrapbook
        case .phone: .talk
        case .plant: .growWithKindness
        }
    }

    var accessibilityHint: String {
        switch self {
        case .plant: "Opens a short game where you read kind words aloud and a plant grows."
        default: ""
        }
    }

    /// Wording from the prototype's hover tooltips.
    var tooltip: String {
        switch self {
        case .ced: "View Today\u{2019}s Activity"
        case .scrapbook: "Open Story"
        case .phone: "Get Support"
        case .plant: "Grow with Kindness"
        }
    }

    /// Where the object sits on the 390 × 700 room grid.
    var frame: CGRect {
        switch self {
        case .ced: CGRect(x: 160, y: 428, width: 70, height: 82)
        case .scrapbook: CGRect(x: 50, y: 480, width: 84, height: 46)
        case .phone: CGRect(x: 247, y: 469, width: 75, height: 55)
        case .plant: PixelRoomPlantArt.frame
        }
    }

    /// Where another object's tooltip must not go: the drawn art, which is a
    /// little narrower than the tap area for Ced (his sides) and the plant
    /// (its leftmost leaves start about 8 units in).
    var keepClearFrame: CGRect {
        switch self {
        case .ced: frame.insetBy(dx: 10, dy: 0)
        case .plant: CGRect(x: frame.minX + 8, y: frame.minY, width: frame.width - 8, height: frame.height)
        default: frame
        }
    }

    /// The object's highest drawn point on the room grid (its art can start
    /// a little below the top of its tap area).
    var visibleTop: CGFloat {
        switch self {
        case .plant: frame.minY + 3   // the plant's top leaf starts 3 units down
        case .ced: frame.minY - 2     // the middle of his 4-unit float: about 3-7 pt as he moves
        default: frame.minY
        }
    }

    @ViewBuilder var artwork: some View {
        switch self {
        case .ced:
            PixelCedArt()
        case .scrapbook:
            PixelScrapbookArt()
        case .plant:
            PixelRoomPlantArt()
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
    var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let glow = configuration.isPressed || isHovered ? Color.white : .clear
        configuration.label
            .shadow(color: glow, radius: 2)
            .shadow(color: glow.opacity(0.55), radius: 4.5)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed || isHovered)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    pressedObject = object
                } else if pressedObject == object {
                    pressedObject = nil
                }
            }
    }
}

/// Where an object's tooltip goes: just above the object (the same small gap
/// for every object), centered over it, sliding sideways a little to clear a
/// neighbour, and always inside the visible screen. Ced's message card ends
/// only a few points above his head, so his tooltip may cover the card while
/// he's pressed (it's drawn in front of it).
enum RoomTooltipLayout {
    /// Space between a tooltip and its object, in screen points.
    static let gap: CGFloat = 5
    /// Kept clear of the screen edges, in screen points.
    static let edgeMargin: CGFloat = 8

    fileprivate static func center(for object: RoomObject, size: CGSize, scale: CGFloat,
                                   visibleLeft: CGFloat, visibleWidth: CGFloat) -> CGPoint {
        let frame = object.frame
        let half = size.width / 2 + edgeMargin
        let onScreen = { (x: CGFloat) in min(max(x, visibleLeft + half), visibleLeft + visibleWidth - half) }
        // Ced's message card (with its 3-unit border). Ced's own tooltip may
        // cover it while he's pressed (it's drawn in front): there's no room
        // between the card and his head.
        let card = scaled(RoomCedMessage.frame.insetBy(dx: -3, dy: -3), by: scale)
        let others = RoomObject.all.filter { $0 != object }.map { scaled($0.keepClearFrame, by: scale) }
        let blockers = object == .ced ? others : [card] + others
        let aboveY = object.visibleTop * scale - gap - size.height / 2
        // Centered first; if a neighbour is in the way, slide sideways by up
        // to half the object's width so the tooltip still sits over it.
        let reach = frame.width * scale / 2
        let shifts: [CGFloat] = [0] + stride(from: CGFloat(4), through: reach, by: 4).flatMap { [-$0, $0] }
        for shift in shifts {
            let x = onScreen(frame.midX * scale + shift)
            let rect = CGRect(x: x - size.width / 2, y: aboveY - size.height / 2, width: size.width, height: size.height)
            if !blockers.contains(where: { rect.intersects($0) }) { return CGPoint(x: x, y: aboveY) }
        }
        return CGPoint(x: onScreen(frame.midX * scale), y: aboveY)   // above, even if snug
    }

    private static func scaled(_ rect: CGRect, by scale: CGFloat) -> CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
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
    .environment(JourneyStore())
}
