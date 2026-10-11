import PhotosUI
import SwiftUI

/// Scrapbook: add a photo from the library and see every photo saved so far.
struct ScrapbookView: View {
    @State private var photos: [ScrapbookPhotoDTO] = []
    @State private var pickedItem: PhotosPickerItem?
    @State private var isLoading = true
    @State private var isUploading = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Look how far you\u{2019}ve come.")
                    .cedTextStyle(.pageTitle)
                    .foregroundStyle(CEDColor.foreground)
                    .accessibilityAddTraits(.isHeader)

                PhotosPicker(selection: $pickedItem, matching: .images) {
                    Text(isUploading ? "Adding\u{2026}" : "Add a memory")
                        .cedTextStyle(.button)
                        .foregroundStyle(CEDColor.cream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(CEDColor.primary, in: RoundedRectangle(cornerRadius: CEDRadius.xl))
                }
                .disabled(isUploading)

                if let errorMessage {
                    Text(errorMessage)
                        .cedTextStyle(.body)
                        .foregroundStyle(CEDColor.rose)
                }

                if isLoading {
                    ProgressView()
                        .tint(CEDColor.primary)
                        .frame(maxWidth: .infinity)
                } else if photos.isEmpty {
                    Text("Your memories will show up here.")
                        .cedTextStyle(.body)
                        .foregroundStyle(CEDColor.mutedForeground)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(photos) { photo in
                        Color.clear
                            .frame(height: 160)
                            .overlay {
                                AsyncImage(url: photo.imageUrl) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    CEDColor.secondary
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: CEDRadius.xl))
                    }
                }
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
        .background(CEDColor.background)
        .task { await load() }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    private func load() async {
        do {
            photos = try await APIClient.shared.scrapbookPhotos()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func upload(_ item: PhotosPickerItem) async {
        isUploading = true
        errorMessage = nil
        defer {
            isUploading = false
            pickedItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = ImageCompressor.jpeg(from: image) else {
                errorMessage = "That photo couldn\u{2019}t be read. Try another one."
                return
            }
            let photo = try await APIClient.shared.uploadScrapbookPhoto(
                jpeg: jpeg,
                caption: nil,
                localDate: CheckInAnswers.localDateText(for: .now)
            )
            photos.insert(photo, at: 0)
        } catch {
            errorMessage = "Your photo wasn\u{2019}t saved. \(error.localizedDescription)"
        }
    }
}