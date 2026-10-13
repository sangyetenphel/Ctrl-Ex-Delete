import PhotosUI
import SwiftUI

/// The reflection for the activity in progress: two questions, optional
/// notes and an optional photo. Saving it completes the activity and adds
/// the memory to the scrapbook. Opening this screen completes nothing.
struct ReflectionView: View {
    @Environment(AppRouter.self) private var router
    @Environment(JourneyStore.self) private var journey

    @State private var note = ""
    @State private var thoughtAboutEx: ThoughtAboutEx?
    @State private var moodChange: MoodChange?
    @State private var noticed = ""

    @State private var pickedItem: PhotosPickerItem?
    @State private var photo: PickedPhoto?
    @State private var isLoadingPhoto = false
    @State private var photoError: String?
    /// Set once the picked photo is in S3, so a retried save doesn't upload it again.
    @State private var uploadedPhotoId: Int?

    @State private var isSaving = false
    @State private var saveError: String?

    private struct PickedPhoto {
        let preview: UIImage
        let jpeg: Data
    }

    var body: some View {
        VStack(spacing: 0) {
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
        }
        .background(CEDColor.background)
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }  // cancelled: keep the current photo
            Task { await loadPhoto(item) }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    photoPicker

                    VStack(alignment: .leading, spacing: 8) {
                        Text("A short note about today").questionLabelStyle()
                        CEDTextArea(text: $note, placeholder: "I felt calmer once I went outside\u{2026}", lines: 3)
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What did you notice?").questionLabelStyle()
                        CEDTextArea(text: $noticed, placeholder: "I felt calmer once I went outside\u{2026}", lines: 2)
                    }

                    VStack(spacing: 12) {
                        PrimaryButton(title: isSaving ? "Saving\u{2026}" : "Add to my scrapbook",
                                      isEnabled: !isSaving && !isLoadingPhoto) {
                            save(current)
                        }
                        if let saveError {
                            Text(saveError)
                                .cedTextStyle(.body)
                                .foregroundStyle(CEDColor.rose)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .padding(24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
    }

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

    /// The prototype's dashed photo box, now opening the system photo picker.
    /// The picker runs outside the app, so no photo-library permission is needed:
    /// the app only receives the one photo the user picks.
    private var photoPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $pickedItem, matching: .images, preferredItemEncoding: .compatible) {
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
                    Text("or continue without one")
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

    private func loadPhoto(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        photoError = nil
        defer { isLoadingPhoto = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = ImageCompressor.jpeg(from: image) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            guard item == pickedItem else { return }  // a newer pick replaced this one
            photo = PickedPhoto(preview: image, jpeg: jpeg)
            uploadedPhotoId = nil
        } catch {
            photoError = "That photo couldn\u{2019}t be opened. Try another one."
        }
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

    /// Checks the two questions, uploads the photo (if any) only now, then
    /// saves the memory, which completes the activity.
    private func save(_ current: SelectedActivity) {
        guard !isSaving else { return }
        guard let thoughtAboutEx, let moodChange else {
            saveError = "Please answer both questions above before saving."
            return
        }
        isSaving = true
        saveError = nil

        Task {
            defer { isSaving = false }
            var photoId = uploadedPhotoId
            if let photo, photoId == nil {
                do {
                    photoId = try await journey.uploadPhoto(jpeg: photo.jpeg)
                    uploadedPhotoId = photoId
                } catch {
                    saveError = "Your photo wasn\u{2019}t uploaded, so nothing was saved yet. \(error.localizedDescription)"
                    return
                }
            }

            do {
                try await journey.saveReflection(ReflectionRequest(
                    activitySelectionId: current.selectionId,
                    thoughtAboutEx: thoughtAboutEx,
                    moodChange: moodChange,
                    note: note.trimmedOrNil,
                    noticed: noticed.trimmedOrNil,
                    photoId: photoId,
                    localDate: CheckInAnswers.localDateText(for: .now)
                ))
                router.go(to: .scrapbook)
            } catch {
                saveError = "Your memory wasn\u{2019}t saved. \(error.localizedDescription)"
            }
        }
    }
}

private extension String {
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    let _ = FontRegistrar.registerBundledFonts()
    ReflectionView()
        .environment(AppRouter(start: .reflection))
        .environment(JourneyStore())
}
