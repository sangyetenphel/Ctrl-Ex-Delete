import AVFoundation
import PhotosUI
import SwiftUI

/// The reflection for the activity in progress: a photo, "What did you
/// notice?" and two questions, all required. Saving it completes
/// the activity and adds the memory to the scrapbook, with a short Ced
/// transition on the way to Story. Opening this screen completes nothing.
struct ReflectionView: View {
    @Environment(AppRouter.self) private var router
    @Environment(JourneyStore.self) private var journey

    @State private var note = ""        // "What did you notice?"
    @State private var thoughtAboutEx: ThoughtAboutEx?
    @State private var moodChange: MoodChange?
    /// Set when "Add to my scrapbook" is tapped with something missing; the
    /// message then shows until everything is filled in.
    @State private var triedIncomplete = false

    @State private var pickedItem: PhotosPickerItem?
    @State private var isChoosingPhotoSource = false
    @State private var isShowingLibrary = false
    @State private var isShowingCamera = false
    @State private var isCameraAccessOff = false
    @State private var photo: PickedPhoto?
    @State private var isLoadingPhoto = false
    @State private var photoError: String?
    /// Set once the picked photo is in S3, so a retried save doesn't upload it again.
    @State private var uploadedPhotoId: Int?

    @State private var phase = Phase.editing
    @State private var saveError: String?

    /// Where the screen is in saving. Everything the user entered lives in
    /// this view's state, so going back to `.editing` after a failure keeps it.
    private enum Phase: Equatable {
        case editing
        case saving          // uploading the photo / saving the memory
        case saved           // saved; loading Story before opening it
        case storyNotLoaded  // saved, but Story couldn't be refreshed
    }

    private var isSaving: Bool { phase != .editing }

    private struct PickedPhoto {
        let preview: UIImage
        let jpeg: Data
    }

    var body: some View {
        VStack(spacing: 0) {
            if phase == .editing {
                header

                if let current = journey.selectedActivity {
                    form(for: current)
                } else if !journey.hasLoaded {
                    ProgressView()
                        .tint(CEDColor.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    noActivityView
                }
            } else {
                // While saving and after, the activity is no longer "in
                // progress", so this replaces the form instead of falling
                // through to "Choose an activity first".
                CedSavingView(
                    state: phase == .saving ? .saving : phase == .saved ? .saved : .storyNotLoaded,
                    onRetry: { Task { await openStory() } },
                    onOpenStory: { router.go(to: .scrapbook) }
                )
                .transition(.opacity)
            }
        }
        .background(CEDColor.background)
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }  // cancelled: keep the current photo
            Task { await loadPhoto(item) }
        }
        // Both photo sources end in usePhoto(_:), so they share the same
        // preview, upload and save, linked to the activity in progress.
        .confirmationDialog(photo == nil ? "Add a photo" : "Change photo",
                            isPresented: $isChoosingPhotoSource, titleVisibility: .visible) {
            Button("Take Photo", action: takePhoto)
            Button("Choose from Library") { isShowingLibrary = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $isShowingLibrary, selection: $pickedItem,
                      matching: .images, preferredItemEncoding: .compatible)
        .fullScreenCover(isPresented: $isShowingCamera) {
            // Cancelling keeps whatever photo was there before.
            CameraPicker(onCapture: { image in
                pickedItem = nil  // forget any library pick, so it can be chosen again
                usePhoto(image)
            }, onCancel: {})
                .ignoresSafeArea()
        }
        .alert("Camera access is off", isPresented: $isCameraAccessOff) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Choose from Library") { isShowingLibrary = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("To take a photo for this memory, allow camera access for Ctrl+Ex+Delete in Settings. You can also choose one from your library.")
        }
    }

    /// Reached with nothing in progress (e.g. from the scrapbook).
    private var noActivityView: some View {
        VStack(spacing: 12) {
            Text("Choose an activity first")
                .cedTextStyle(.cardTitle)
                .foregroundStyle(CEDColor.foreground)
            Text("Reflections belong to an activity. Pick one that feels doable, and come back here once you\u{2019}ve tried it.")
                .cedTextStyle(.body)
                .foregroundStyle(CEDColor.mutedForeground)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "Choose an activity") {
                router.go(to: .activities)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .padding(.top, 24)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func form(for current: SelectedActivity) -> some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    photoPicker

                    // One text answer: it becomes the memory's quote in Story.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What did you notice?").questionLabelStyle()
                        CEDTextArea(text: $note,
                                    placeholder: "A thought, a feeling, or a small moment from your activity\u{2026}",
                                    lines: 3)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Did you think about your ex during the activity?").questionLabelStyle()
                        HStack(spacing: 8) {
                            ForEach(ThoughtAboutEx.allCases) { option in
                                OptionButton(title: option.label, isSelected: thoughtAboutEx == option, verticalPadding: 10) {
                                    thoughtAboutEx = option
                                }
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("How do you feel now compared to before?").questionLabelStyle()
                        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                            GridRow {
                                moodButton(.worse)
                                moodButton(.aboutTheSame)
                            }
                            GridRow {
                                moodButton(.aLittleBetter)
                                moodButton(.muchBetter)
                            }
                        }
                    }

                    VStack(spacing: 12) {
                        // The one message for anything missing, right above the button.
                        if showsMissingMessage {
                            Text("Please add a photo and answer all questions above.")
                                .cedTextStyle(.body)
                                .foregroundStyle(CEDColor.rose)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .transition(.opacity)
                        }

                        PrimaryButton(title: isSaving ? "Saving\u{2026}" : "Add to my scrapbook",
                                      isEnabled: !isSaving && !isLoadingPhoto) {
                            if !save(current) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    scroller.scrollTo(Self.submitArea, anchor: .bottom)
                                }
                            }
                        }

                        // Upload and network problems, kept apart from missing inputs.
                        if let saveError {
                            Text(saveError)
                                .cedTextStyle(.body)
                                .foregroundStyle(CEDColor.rose)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .id(Self.submitArea)
                    .animation(.easeOut(duration: 0.2), value: showsMissingMessage)
                    .padding(.bottom, 8)
                }
                .padding(24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .onChange(of: isComplete) { _, complete in
            if complete { triedIncomplete = false }  // clear the message once all is filled in
        }
    }

    private static let submitArea = "submitArea"

    /// Every input is required: a photo, a non-blank note and both answers.
    private var isComplete: Bool {
        ReflectionDraft.isComplete(hasPhoto: photo != nil, note: note,
                                   thoughtAboutEx: thoughtAboutEx, moodChange: moodChange)
    }

    private var showsMissingMessage: Bool { triedIncomplete && !isComplete }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            IconBadge {
                CEDIconView(icon: .check, size: 20, color: CEDColor.primary)
            }
            .padding(.bottom, 12)

            Text("You showed up.")
                .cedTextStyle(.pageTitle)
                .foregroundStyle(CEDColor.foreground)
                .accessibilityAddTraits(.isHeader)

            Text("Add a small piece of today to your scrapbook.")
                .cedTextStyle(.body)
                .foregroundStyle(CEDColor.mutedForeground)
                .padding(.top, 4)

            if let activity = journey.selectedActivity?.activity {
                selectedActivityRow(activity)
                    .padding(.top, 12)
            }
        }
        .cardHeaderStyle()
    }

    /// The activity in progress, which this reflection completes.
    private func selectedActivityRow(_ activity: Activity) -> some View {
        HStack(alignment: .top, spacing: 10) {
            CEDIconView(icon: activity.icon, size: 18, color: activity.accent)
                .frame(width: 36, height: 36)
                .background(activity.background, in: RoundedRectangle(cornerRadius: CEDRadius.lg))
            VStack(alignment: .leading, spacing: 0) {
                Text(activity.category)
                    .cedTextStyle(.captionBold)
                    .foregroundStyle(activity.accent)
                Text(activity.title)
                    .cedTextStyle(.bodySemibold)
                    .foregroundStyle(CEDColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(activity.instructions)
                    .cedTextStyle(.caption)
                    .foregroundStyle(CEDColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reflecting on: \(activity.title)")
    }

    // MARK: Photo

    /// The prototype's dashed photo box. Tapping it offers the camera or the
    /// photo library. The library picker runs outside the app, so it needs no
    /// permission; the camera asks for permission the first time it's used.
    private var photoPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: choosePhotoSource) {
                photoBox
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .accessibilityLabel(photo == nil ? "Add a photo" : "Change photo")
            .overlay(alignment: .topTrailing) {
                if photo != nil, !isSaving {
                    Button(action: removePhoto) {
                        CEDIconView(icon: .xMark, size: 16, color: CEDColor.foreground)
                            .frame(width: 32, height: 32)
                            .background(.white.opacity(0.85), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .accessibilityLabel("Remove photo")
                }
            }

            if let photoError {
                Text(photoError)
                    .cedTextStyle(.caption)
                    .foregroundStyle(CEDColor.rose)
            }
        }
    }

    private var photoBox: some View {
        let shape = RoundedRectangle(cornerRadius: CEDRadius.xl)
        return ZStack {
            if let photo {
                Color.clear
                    .overlay {
                        Image(uiImage: photo.preview)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .overlay(alignment: .bottom) {
                        Text("Change photo")
                            .cedTextStyle(.captionBold)
                            .foregroundStyle(CEDColor.foreground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.85), in: Capsule())
                            .padding(.bottom, 10)
                    }
            } else if isLoadingPhoto {
                ProgressView()
                    .tint(CEDColor.primary)
            } else {
                VStack(spacing: 8) {
                    CEDIconView(icon: .image, size: 32, color: CEDColor.mutedForeground)
                    Text("Add a photo")
                        .cedTextStyle(.bodySemibold)
                        .foregroundStyle(CEDColor.mutedForeground)
                    Text("Take one or choose from your library.")
                        .cedTextStyle(.caption)
                        .foregroundStyle(CEDColor.hint)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: photo == nil ? 144 : 220)
        .background(CEDColor.card, in: shape)
        .clipShape(shape)
        .overlay {
            if photo == nil {
                shape.strokeBorder(CEDColor.border, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
        }
        .contentShape(shape)
    }

    /// Without a camera (e.g. the Simulator), go straight to the library.
    private func choosePhotoSource() {
        photoError = nil
        if CameraPicker.isAvailable {
            isChoosingPhotoSource = true
        } else {
            isShowingLibrary = true
        }
    }

    /// "Take Photo": opens the camera, asking for permission only if needed.
    private func takePhoto() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch CameraRoute.route(isCameraAvailable: CameraPicker.isAvailable, status: status) {
        case .open:
            isShowingCamera = true
        case .askPermission:
            Task {
                if await AVCaptureDevice.requestAccess(for: .video) {
                    isShowingCamera = true
                } else {
                    isCameraAccessOff = true
                }
            }
        case .denied:
            isCameraAccessOff = true
        case .unavailable:
            photoError = "This device doesn\u{2019}t have a camera. Choose a photo from your library instead."
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        photoError = nil
        defer { isLoadingPhoto = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            guard item == pickedItem else { return }  // a newer pick replaced this one
            usePhoto(image)
        } catch {
            photoError = "That photo couldn\u{2019}t be opened. Try another one."
        }
    }

    /// The one place a photo from either source becomes the memory's photo.
    /// It's shrunk now and uploaded only when the memory is saved.
    private func usePhoto(_ image: UIImage) {
        guard let jpeg = ImageCompressor.jpeg(from: image) else {
            photoError = "That photo couldn\u{2019}t be used. Try another one."
            return
        }
        // Preview the shrunk copy, so a full-size camera photo isn't kept in memory.
        photo = PickedPhoto(preview: UIImage(data: jpeg) ?? image, jpeg: jpeg)
        uploadedPhotoId = nil  // a new photo needs a new upload
        photoError = nil
    }

    private func removePhoto() {
        photo = nil
        pickedItem = nil
        uploadedPhotoId = nil
        photoError = nil
    }

    // MARK: Saving

    private func moodButton(_ option: MoodChange) -> some View {
        OptionButton(title: option.label, isSelected: moodChange == option) {
            moodChange = option
        }
    }

    /// Checks every input first, then uploads the photo, then saves the memory,
    /// which completes the activity. Nothing is uploaded or saved while
    /// anything is missing. Returns false if something was missing.
    @discardableResult
    private func save(_ current: SelectedActivity) -> Bool {
        guard phase == .editing else { return true }  // no double submits
        guard isComplete, let photo, let note = ReflectionDraft.trimmedNote(note),
              let thoughtAboutEx, let moodChange else {
            triedIncomplete = true
            AccessibilityNotification.Announcement("Please add a photo and answer all questions above.").post()
            return false
        }
        triedIncomplete = false
        saveError = nil
        withAnimation(.easeInOut(duration: 0.25)) { phase = .saving }

        Task {
            let photoId: Int
            if let alreadyUploaded = uploadedPhotoId {
                photoId = alreadyUploaded  // a retry doesn't upload it again
            } else {
                do {
                    photoId = try await journey.uploadPhoto(jpeg: photo.jpeg)
                    uploadedPhotoId = photoId
                } catch {
                    backToForm(error: "Your photo wasn\u{2019}t uploaded, so nothing was saved yet. \(error.localizedDescription)")
                    return
                }
            }

            do {
                try await journey.saveReflection(ReflectionRequest(
                    activitySelectionId: current.selectionId,
                    thoughtAboutEx: thoughtAboutEx,
                    moodChange: moodChange,
                    note: note,
                    photoId: photoId,
                    localDate: CheckInAnswers.localDateText(for: .now)
                ))
            } catch {
                // A photo the server no longer has (404) is uploaded again on retry.
                if case APIError.server(status: 404, _) = error { uploadedPhotoId = nil }
                backToForm(error: "Your memory wasn\u{2019}t saved. \(error.localizedDescription) Your answers and photo are still here, so you can try again.")
                return
            }

            // Saved: only now show the success message.
            withAnimation(.easeInOut(duration: 0.3)) { phase = .saved }
            AccessibilityNotification.Announcement("You showed up. One small step deserves a place in your story.").post()
            await openStory()
        }
        return true
    }

    private func backToForm(error message: String) {
        saveError = message
        withAnimation(.easeInOut(duration: 0.25)) { phase = .editing }
    }

    /// After a successful save: refresh Story (retrying a few times), keep
    /// the success message up long enough to read, then open Story with the
    /// new memory. Never saves again, so a failed refresh can't duplicate it.
    private func openStory() async {
        if phase == .storyNotLoaded {
            withAnimation(.easeInOut(duration: 0.25)) { phase = .saved }
        }
        let shownAt = ContinuousClock.now
        var loaded = false
        for attempt in 1...3 {
            do {
                try await journey.reloadStory()
                loaded = true
                break
            } catch {
                if attempt < 3 { try? await Task.sleep(for: .seconds(attempt)) }
            }
        }
        guard loaded else {
            withAnimation(.easeInOut(duration: 0.25)) { phase = .storyNotLoaded }
            return
        }
        let minimum = Duration.milliseconds(1800)
        let elapsed = ContinuousClock.now - shownAt
        if elapsed < minimum { try? await Task.sleep(for: minimum - elapsed) }
        router.go(to: .scrapbook)
    }
}

#Preview {
    let _ = FontRegistrar.registerBundledFonts()
    ReflectionView()
        .environment(AppRouter(start: .reflection))
        .environment(JourneyStore())
}
