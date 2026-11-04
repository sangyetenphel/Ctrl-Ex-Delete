import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// The farewell gift, reached only from "I'm ready to move forward":
/// 1. Ced puts the scrapbook together (the real PDF is made meanwhile, from
///    the latest journey: everything it has, nothing to choose).
/// 2. Only once that worked: "Before you go, I made you something."
/// 3. "Open my gift" shows that same scrapbook with "Save my scrapbook".
/// Every visit makes a fresh one. Nothing is deleted, locked or shared
/// unless the user shares it.
struct FinalGiftView: View {
    @Environment(AppRouter.self) private var router
    @State private var gift = FarewellGift()
    /// The animation has had its moment, so the invitation may show.
    @State private var isPrepared = false
    @State private var isOpened = false
    /// The PDF being handed to the Files export screen.
    @State private var exportDocument: ScrapbookDocument?
    @State private var isExporting = false
    @State private var isSavedMessageShown = false
    @State private var savedMessageTask: Task<Void, Never>?
    @State private var saveError: String?

    /// Long enough to see Ced at work, short enough not to keep anyone waiting.
    private static let minimumAnimation = Duration.seconds(2.6)
    private static let savedMessage = "Your scrapbook has been saved!"

    var body: some View {
        Group {
            switch gift.phase {
            case .idle, .preparing:
                preparing
            case .ready(let url):
                if !isPrepared {
                    preparing
                } else if isOpened {
                    reveal(url)
                } else {
                    invitation
                }
            case .photosUnavailable(let count):
                problem(
                    title: count == 1 ? "One photo couldn\u{2019}t be loaded" : "\(count) photos couldn\u{2019}t be loaded",
                    message: "Check your connection and try again. Or make your scrapbook without \(count == 1 ? "it" : "them"); the page will say where a photo couldn\u{2019}t be included.",
                    secondary: ("Make it without \(count == 1 ? "it" : "them")", { make(withoutMissingPhotos: true) })
                )
            case .failed(let message):
                problem(title: "Your scrapbook couldn\u{2019}t be made", message: message, secondary: nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CEDColor.background)
        // Straight into the animation; the scrapbook is made meanwhile.
        .task { make() }
        .onDisappear { savedMessageTask?.cancel() }
    }

    // MARK: 1. Making it

    private var preparing: some View {
        VStack(spacing: 20) {
            Spacer()
            ScrapbookAssemblyView()
            Text("Ced is putting your scrapbook together\u{2026}")
                .cedTextStyle(.bodyBold)
                .foregroundStyle(CEDColor.foreground)
            Text("Gathering your photos and words.")
                .cedTextStyle(.body)
                .foregroundStyle(CEDColor.mutedForeground)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }

    // MARK: 2. The invitation (only after it was made)

    private var invitation: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    CedPresentingGift(size: 112)
                    Text("Before you go, I made you something.")
                        .cedTextStyle(.finalTitle)
                        .foregroundStyle(CEDColor.foreground)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text("A few pieces of your story, gathered with care.")
                        .cedTextStyle(.bodyRelaxed)
                        .foregroundStyle(CEDColor.mutedForeground)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)

                PrimaryButton(title: "Open my gift") {
                    withAnimation(.easeInOut(duration: 0.3)) { isOpened = true }
                }

                roomLink

                Text("Your scrapbook is made on this phone. Nothing is shared unless you choose to share it.")
                    .cedTextStyle(.caption)
                    .foregroundStyle(CEDColor.hint)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: 3. The gift

    private func reveal(_ url: URL) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("This chapter belongs to you.")
                    .cedTextStyle(.pageTitle)
                    .foregroundStyle(CEDColor.foreground)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("A little gift from me to you, filled with the moments you made your own.")
                    .cedTextStyle(.body)
                    .foregroundStyle(CEDColor.mutedForeground)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 16)

            PDFPreview(url: url)
                .clipShape(RoundedRectangle(cornerRadius: CEDRadius.xl))
                .overlay(RoundedRectangle(cornerRadius: CEDRadius.xl).strokeBorder(CEDColor.border, lineWidth: 1))
                .accessibilityLabel("Preview of your scrapbook")
                .overlay(alignment: .bottom) {
                    if isSavedMessageShown {
                        ToastView(message: Self.savedMessage)
                            .padding(.bottom, 12)
                            .transition(.opacity)
                    }
                }

            Button {
                save(url)
            } label: {
                HStack(spacing: 8) {
                    CEDIconView(icon: .download, size: 20, color: CEDColor.cream)
                    Text("Save my scrapbook")
                }
                .cedTextStyle(.button)
                .foregroundStyle(CEDColor.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(CEDColor.primary, in: RoundedRectangle(cornerRadius: CEDRadius.xl))
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityHint("Opens Files, where you choose where to save it.")

            if let saveError {
                Text(saveError)
                    .cedTextStyle(.body)
                    .foregroundStyle(CEDColor.rose)
                    .multilineTextAlignment(.center)
            }

            roomLink
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .fileExporter(isPresented: $isExporting, document: exportDocument, contentType: .pdf,
                      defaultFilename: FarewellGift.fileName, onCompletion: finishSaving)
    }

    // MARK: Saving to Files

    /// Opens the system's Files export screen with the PDF already made.
    private func save(_ url: URL) {
        saveError = nil
        savedMessageTask?.cancel()
        isSavedMessageShown = false
        do {
            exportDocument = ScrapbookDocument(data: try Data(contentsOf: url))
            isExporting = true
        } catch {
            saveError = Self.saveFailedMessage
        }
    }

    /// Runs only when the export screen reports a result. Cancelling isn't one
    /// of them, so it shows nothing.
    private func finishSaving(_ result: Result<URL, any Error>) {
        switch result {
        case .success:
            showSavedMessage()
        case .failure:
            saveError = Self.saveFailedMessage
        }
    }

    private func showSavedMessage() {
        savedMessageTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { isSavedMessageShown = true }
        AccessibilityNotification.Announcement(Self.savedMessage).post()
        savedMessageTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { isSavedMessageShown = false }
        }
    }

    private static let saveFailedMessage = "Your scrapbook wasn\u{2019}t saved. Please try again, or choose a different location."

    // MARK: Problems

    private func problem(title: String, message: String, secondary: (String, () -> Void)?) -> some View {
        VStack(spacing: 16) {
            Spacer()
            GhostView(size: 72)
            Text(title)
                .cedTextStyle(.cardTitle)
                .foregroundStyle(CEDColor.foreground)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .cedTextStyle(.body)
                .foregroundStyle(CEDColor.mutedForeground)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "Try again") { make() }
                .padding(.top, 8)
            if let (label, action) = secondary {
                OutlineButton(title: label, color: CEDColor.primary, action: action)
            }
            roomLink
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var roomLink: some View {
        Button("Back to my room") { router.go(to: .room) }
            .cedTextStyle(.bodySemibold)
            .foregroundStyle(CEDColor.mutedForeground)
    }

    // MARK: Making it

    /// Runs the animation while the scrapbook is made, and shows the
    /// invitation only once the file exists. Repeated taps do nothing extra
    /// (FarewellGift never makes two at once, nor a second one per visit).
    private func make(withoutMissingPhotos: Bool = false) {
        guard gift.phase != .preparing else { return }
        isPrepared = false
        Task {
            let started = ContinuousClock.now
            await gift.prepare(withoutMissingPhotos: withoutMissingPhotos)
            guard case .ready = gift.phase else { return }
            let elapsed = ContinuousClock.now - started
            if elapsed < Self.minimumAnimation { try? await Task.sleep(for: Self.minimumAnimation - elapsed) }
            withAnimation(.easeInOut(duration: 0.4)) { isPrepared = true }
            AccessibilityNotification.Announcement("Ced made you something.").post()
        }
    }
}

// MARK: - PDF preview

private struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(CEDColor.secondary)
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}

#Preview {
    let _ = FontRegistrar.registerBundledFonts()
    FinalGiftView()
        .environment(AppRouter(start: .finalGift))
}
