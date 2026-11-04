import SwiftUI
import UniformTypeIdentifiers

/// Prepares the farewell scrapbook: loads the latest journey, downloads the
/// real photo bytes and draws the PDF off the main thread. A new one is made
/// on every readiness attempt, with everything the journey has (nothing to
/// choose); an earlier copy is never reused. Nothing in the journey changes.
@Observable
final class FarewellGift {
    enum Phase: Equatable {
        case idle
        case preparing
        /// Some photos couldn't be downloaded. The user chooses: try again,
        /// or make the scrapbook without them (it then says so on the page).
        case photosUnavailable(count: Int)
        case failed(String)
        case ready(URL)
    }

    private(set) var phase = Phase.idle
    /// Downloaded photos (by photo id), kept between retries of this attempt.
    private var photos: [Int: Data] = [:]

    init() {
        // Left by an earlier version that let people leave things out.
        UserDefaults.standard.removeObject(forKey: "farewellScrapbookExclusions")
    }

    /// Makes this attempt's scrapbook. `withoutMissingPhotos` is the user's
    /// explicit choice to continue when some photos couldn't be downloaded.
    func prepare(withoutMissingPhotos: Bool = false) async {
        guard phase != .preparing else { return }   // never two at once
        if case .ready = phase { return }           // this attempt's scrapbook is done
        phase = .preparing
        Self.removeOldCopies()
        do {
            // The latest journey, with fresh private photo links.
            let journey = try await APIClient.shared.farewellScrapbook()

            let wanted = Self.photoRequests(in: journey).filter { photos[$0.id] == nil }
            let downloaded = await Self.download(wanted)
            photos.merge(downloaded) { _, new in new }
            let missing = Set(wanted.map(\.id)).subtracting(downloaded.keys)
            if !missing.isEmpty && !withoutMissingPhotos {
                phase = .photosUnavailable(count: missing.count)
                return
            }

            var content = Self.content(from: journey, photos: photos)
            content.cedImage = ScrapbookArtwork.ced()
            content.scrapbookImage = ScrapbookArtwork.scrapbook()
            let finished = content

            let url = try await Task.detached(priority: .userInitiated) {
                let data = ScrapbookPDF.render(finished)
                return try FarewellGift.store(data)
            }.value
            phase = .ready(url)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: Photos

    private struct PhotoRequest: Sendable {
        let id: Int
        let url: URL?
    }

    private static func photoRequests(in journey: FarewellScrapbookDTO) -> [PhotoRequest] {
        let memories = journey.completedActivities.compactMap(\.memory) + journey.otherMemories
        return memories.compactMap { memory in
            memory.photoId.map { PhotoRequest(id: $0, url: memory.imageUrl) }
        }
    }

    /// Downloads up to four photos at a time. A link that fails (expired,
    /// refused) is refreshed once through the backend; the bucket stays private.
    private static func download(_ requests: [PhotoRequest]) async -> [Int: Data] {
        await withTaskGroup(of: (Int, Data?).self) { group in
            var results: [Int: Data] = [:]
            var pending = requests[...]
            func startNext() {
                guard let request = pending.popFirst() else { return }
                group.addTask { (request.id, await fetch(request)) }
            }
            for _ in 0..<4 { startNext() }
            for await (id, data) in group {
                if let data { results[id] = data }
                startNext()
            }
            return results
        }
    }

    private nonisolated static func fetch(_ request: PhotoRequest) async -> Data? {
        if let url = request.url, let data = try? await APIClient.shared.downloadPhoto(from: url),
           let small = await compress(data) {
            return small
        }
        guard let fresh = try? await APIClient.shared.scrapbookPhoto(id: request.id),
              let data = try? await APIClient.shared.downloadPhoto(from: fresh.imageUrl) else { return nil }
        return await compress(data)
    }

    /// At most 1400 px on the long side, JPEG quality 0.72: sharp on a page,
    /// small enough to share.
    private nonisolated static func compress(_ data: Data) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data) else { return nil }
            let longest = max(image.size.width, image.size.height)
            let scale = min(1, 1400 / max(longest, 1))
            let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            return resized.jpegData(compressionQuality: 0.72)
        }.value
    }

    // MARK: Content

    /// The completed activities, photos and the user's own reflection text,
    /// oldest first; empty parts are simply left out. Check-in answers and
    /// the reflection questions aren't passed to the PDF at all.
    private static func content(from journey: FarewellScrapbookDTO, photos: [Int: Data]) -> ScrapbookContent {
        func day(_ text: String) -> String { LocalDate.format(text, .dateTime.month(.wide).day()) }
        func shortDay(_ text: String) -> String { LocalDate.format(text, .dateTime.month(.abbreviated).day()) }
        let full = Date.FormatStyle.dateTime.month(.wide).day().year()

        func memory(_ dto: FarewellMemoryDTO) -> ScrapbookContent.Memory {
            let wantsPhoto = dto.photoId != nil
            let photo = dto.photoId.flatMap { photos[$0] }
            return .init(date: day(dto.localDate), shortDate: shortDay(dto.localDate), note: dto.note,
                         photo: wantsPhoto ? photo : nil, photoNotIncluded: wantsPhoto && photo == nil)
        }

        var content = ScrapbookContent()
        if let start = journey.journeyStartedOn ?? journey.journeyLastOn {
            let end = journey.journeyLastOn ?? start
            content.dateRange = start == end
                ? LocalDate.format(start, full)
                : "\(LocalDate.format(start, .dateTime.month(.wide).day())) \u{2013} \(LocalDate.format(end, full))"
        }

        content.entries = journey.completedActivities.map {
            .init(date: day($0.completedOn), shortDate: shortDay($0.completedOn), title: $0.activity.title,
                  category: $0.activity.categoryLabel, memory: $0.memory.map(memory))
        }
        content.otherMemories = journey.otherMemories.map(memory)
        return content
    }

    // MARK: The file

    nonisolated static let fileName = "My Ctrl+Ex+Delete Scrapbook.pdf"

    private nonisolated static var directory: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "FarewellScrapbook", directoryHint: .isDirectory)
    }

    nonisolated static func store(_ data: Data) throws -> URL {
        guard let directory else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: fileName)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }

    /// An earlier scrapbook is never shown again: each attempt starts clean.
    private nonisolated static func removeOldCopies() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}

/// The finished PDF, for the system's Files export screen. It only carries
/// the bytes `FarewellGift` already made; nothing is drawn again.
nonisolated struct ScrapbookDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// The app's own Ced and scrapbook artwork as PNGs for the PDF, drawn by
/// the same SwiftUI views the app uses (never redrawn or reshaped).
enum ScrapbookArtwork {
    static func ced() -> Data? {
        png(GhostView(size: 120))
    }

    static func scrapbook() -> Data? {
        png(PixelScrapbookArt().frame(width: 168, height: 92))
    }

    private static func png(_ view: some View) -> Data? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage?.pngData()
    }
}
