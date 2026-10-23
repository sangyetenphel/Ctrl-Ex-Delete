import SwiftUI

/// One "Grow with Kindness" session: three affirmations, one leaf each.
/// Kept only while the game screen is open; nothing is saved or sent.
@Observable
@MainActor
final class KindnessGame {
    enum Phase: Equatable {
        case reading          // reading the current affirmation
        case grown            // its leaf just grew; waiting for "Next"
        case finished         // three leaves and a flower
    }

    static let sentencesPerGame = 3

    private(set) var phase = Phase.reading
    private(set) var session: [Affirmation] = []
    private(set) var index = 0
    private(set) var leaves = 0
    var isQuietPractice = false

    let listener = AffirmationListener()
    /// The catalog this game draws from; a background refresh only affects the next game.
    private var catalog: [Affirmation]
    /// Every sentence shown this game (completed or replaced), never offered again.
    private var used: Set<String> = []

    init(catalog: [Affirmation]) {
        self.catalog = catalog
        listener.onComplete = { [weak self] in self?.completeCurrent() }
        newGame()
    }

    var current: Affirmation? { session.indices.contains(index) ? session[index] : nil }
    var canTryAnother: Bool {
        phase == .reading && current.map { AffirmationCatalog.replacement(for: $0, in: catalog, excluding: used) != nil } ?? false
    }

    func newGame(catalog newCatalog: [Affirmation]? = nil) {
        listener.stop()
        if let newCatalog, newCatalog.count >= Self.sentencesPerGame { catalog = newCatalog }
        session = AffirmationCatalog.pickSession(from: catalog, count: Self.sentencesPerGame)
        used = Set(session.map(\.id))
        index = 0
        leaves = 0
        phase = .reading
        prepareCurrent()
    }

    /// "Try another affirmation": stops listening first; earns nothing.
    func tryAnother() {
        guard phase == .reading, let current,
              let replacement = AffirmationCatalog.replacement(for: current, in: catalog, excluding: used) else { return }
        listener.stop()
        session[index] = replacement
        used.insert(replacement.id)
        prepareCurrent()
    }

    /// "I said it" or "I'm ready": counts the sentence without claiming it was recognised.
    func completeManually() {
        guard phase == .reading else { return }
        listener.markCompletedManually()
        completeCurrent()
    }

    /// One leaf per sentence, however many times this is reached.
    private func completeCurrent() {
        guard phase == .reading else { return }
        leaves += 1
        phase = leaves >= Self.sentencesPerGame ? .finished : .grown
        AccessibilityNotification.Announcement(phase == .finished
            ? "A third leaf grew, and your plant bloomed." : "A new leaf grew.").post()
    }

    /// "Next": only ever from the user's tap. Recording doesn't start by itself.
    func next() {
        guard phase == .grown, index + 1 < session.count else { return }
        index += 1
        phase = .reading
        prepareCurrent()
    }

    private func prepareCurrent() {
        if let current { listener.prepare(for: current.text) }
    }
}

/// The game screen, opened from the room's big plant.
struct GrowWithKindnessView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var game = KindnessGame(catalog: AffirmationCatalog.load())

    private var listener: AffirmationListener { game.listener }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            // The words scroll (large text, long messages); the plant below
            // stays anchored in the same place for the whole game.
            ScrollView {
                VStack(spacing: 18) {
                    if game.phase == .finished {
                        closingCard
                    } else {
                        affirmationCard
                        controls
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            KindnessPlantView(leaves: game.leaves, isBloomed: game.phase == .finished)
                // Smaller with very large text, so the words keep most of the screen.
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 150 : 230)
                .padding(.bottom, 16)
        }
        .background(CEDColor.background)
        // The catalog refreshes in the background for next time only.
        .task { await AffirmationCatalog.refresh() }
        // Leaving or backgrounding always stops the microphone; a tap resumes.
        .onDisappear { listener.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { listener.stop() }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button {
                listener.stop()
                router.go(to: .room)
            } label: {
                CEDIconView(icon: .xMark, size: 20, color: CEDColor.foreground)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
            .accessibilityHint("Goes back to your room.")

            Spacer()
            Text("Grow with Kindness")
                .cedTextStyle(.sectionTitle)
                .foregroundStyle(CEDColor.foreground)
                .accessibilityAddTraits(.isHeader)
            Spacer()

            Text(game.phase == .finished ? "3 of 3" : "\(game.index + 1) of \(KindnessGame.sentencesPerGame)")
                .cedTextStyle(.captionBold)
                .foregroundStyle(CEDColor.mutedForeground)
                .frame(minWidth: 44)
                .accessibilityLabel(game.phase == .finished ? "All three affirmations"
                                    : "Affirmation \(game.index + 1) of \(KindnessGame.sentencesPerGame)")
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    // MARK: The affirmation

    private var affirmationCard: some View {
        VStack(spacing: 16) {
            highlightedSentence
                .cedTextStyle(.cardTitle)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(game.current?.text ?? "")
                .accessibilityValue(accessibilityProgress)

            if game.phase == .reading && !game.isQuietPractice {
                microphoneButton
            }
            statusText
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .background(CEDColor.card, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0x8A4A1C), lineWidth: 3))
    }

    /// The sentence, with every word heard so far in soft green.
    private var highlightedSentence: Text {
        let green = listener.greenWords
        var text = AttributedString()
        for (index, word) in listener.displayWords.enumerated() {
            var piece = AttributedString(index == 0 ? word : " " + word)
            piece.foregroundColor = green.contains(index) || game.phase != .reading
                ? Color(hex: 0x4E9A3A) : CEDColor.foreground
            text += piece
        }
        return Text(text)
    }

    private var accessibilityProgress: String {
        if game.phase != .reading { return "Done" }
        let heard = listener.greenWords.count
        return heard == 0 ? "" : "\(heard) of \(listener.displayWords.count) words heard"
    }

    private var microphoneButton: some View {
        let isListening = listener.state == .listening
        return Button {
            Task { await listener.toggle() }
        } label: {
            ZStack {
                Circle()
                    .fill(isListening ? CEDColor.rose : CEDColor.primary)
                    .frame(width: 60, height: 60)
                if isListening && !reduceMotion {
                    Circle()
                        .strokeBorder(CEDColor.rose.opacity(0.35), lineWidth: 4)
                        .frame(width: 74, height: 74)
                        .phaseAnimator([0.9, 1.08]) { ring, scale in ring.scaleEffect(scale) }
                            animation: { _ in .easeInOut(duration: 0.8) }
                }
                if listener.state == .preparing || listener.state == .processing {
                    ProgressView().tint(CEDColor.cream)
                } else {
                    CEDIconView(icon: .micBold, size: 26, color: CEDColor.cream)
                }
            }
            .frame(width: 76, height: 76)
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(listener.state == .processing)
        .accessibilityLabel(isListening ? "Stop listening" : "Read it aloud")
        .accessibilityHint(isListening ? "Stops the microphone." : "Starts the microphone so the words light up as you say them.")
    }

    @ViewBuilder private var statusText: some View {
        if game.phase == .grown {
            Text("A new leaf grew.")
                .cedTextStyle(.bodySemibold)
                .foregroundStyle(Color(hex: 0x4E8A3A))
        } else if game.isQuietPractice {
            Text("Read it quietly to yourself, then tap \u{201C}I\u{2019}m ready.\u{201D}")
                .cedTextStyle(.body)
                .foregroundStyle(CEDColor.mutedForeground)
                .multilineTextAlignment(.center)
        } else {
            switch listener.state {
            case .idle:
                Text(listener.greenWords.isEmpty ? "Tap the microphone and read it aloud."
                     : "Tap the microphone to carry on where you left off.")
                    .statusStyle()
            case .preparing:
                Text("Getting the microphone ready\u{2026}").statusStyle()
            case .listening:
                Text("Listening\u{2026}").statusStyle()
            case .processing:
                Text("Catching your last words\u{2026}").statusStyle()
            case .retry(let message), .unavailable(let message):
                Text(message).statusStyle()
            }
        }
    }

    // MARK: Controls under the card

    @ViewBuilder private var controls: some View {
        VStack(spacing: 12) {
            switch game.phase {
            case .grown:
                PrimaryButton(title: "Next") { game.next() }
            case .reading:
                if game.isQuietPractice {
                    PrimaryButton(title: "I\u{2019}m ready") { game.completeManually() }
                } else if case .retry = listener.state {
                    OutlineButton(title: "I said it", color: CEDColor.primary) { game.completeManually() }
                }
                HStack(spacing: 20) {
                    if game.canTryAnother {
                        Button("Try another affirmation") { game.tryAnother() }
                            .accessibilityHint("Shows a different sentence. It doesn\u{2019}t count as a leaf.")
                    }
                    Button(game.isQuietPractice ? "Use my voice" : "Practice quietly") {
                        listener.stop()
                        game.isQuietPractice.toggle()
                    }
                }
                .cedTextStyle(.bodySemibold)
                .foregroundStyle(CEDColor.primary)
                .multilineTextAlignment(.center)
            case .finished:
                EmptyView()
            }
        }
    }

    // MARK: The end

    private var closingCard: some View {
        VStack(spacing: 18) {
            Text("A little kindness helps you grow.")
                .cedTextStyle(.cardTitle)
                .foregroundStyle(CEDColor.foreground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.vertical, 26)
                .background(CEDColor.card, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0x8A4A1C), lineWidth: 3))
                .accessibilityAddTraits(.isHeader)
            PrimaryButton(title: "Back to room") { router.go(to: .room) }
            OutlineButton(title: "Play again", color: CEDColor.primary) {
                withAnimation(.easeInOut(duration: 0.3)) { game.newGame(catalog: AffirmationCatalog.load()) }
            }
        }
    }
}

private extension Text {
    func statusStyle() -> some View {
        self.cedTextStyle(.body)
            .foregroundStyle(CEDColor.mutedForeground)
            .multilineTextAlignment(.center)
    }
}

#Preview {
    let _ = FontRegistrar.registerBundledFonts()
    GrowWithKindnessView()
        .environment(AppRouter(start: .growWithKindness))
}
