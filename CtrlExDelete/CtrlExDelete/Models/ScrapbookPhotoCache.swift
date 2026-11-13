import CryptoKit
import Foundation
import ImageIO
import OSLog
import UIKit

/// Keeps the Story screen's memory photos so they appear at once.
///
/// Every refresh of the journey gets fresh, temporary S3 links for the
/// photos, so the links change while the photos don't. Photos are therefore
/// kept by the link's object path (`/scrapbook/<random>.jpg`, the same on
/// every link to that photo), not by the whole link:
/// - in memory: decoded copies, shrunk to what a Story card needs;
/// - on disk: the downloaded JPEG bytes, in Caches/ScrapbookPhotos/<this
///   installation's ID>/, so they're there after a relaunch (the system may
///   empty Caches when space is short; then they're downloaded again).
/// A photo is downloaded only when neither has it, and only once at a time.
/// Nothing is ever uploaded or changed on the server.
nonisolated final class ScrapbookPhotoCache: @unchecked Sendable {
    static let shared = ScrapbookPhotoCache()

    /// The smallest size a Story card needs, in pixels: about 600 px wide
    /// (a card is ~175 pt wide at 3x) and 288 px tall (96 pt at 3x).
    static let minimumPixelSize = CGSize(width: 600, height: 288)

    private let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 60
        return cache
    }()
    private let lock = NSLock()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var memoryKeys: Set<String> = []

    /// The shrunk photo if it's already in memory (no waiting), else nil.
    func cachedImage(for url: URL) -> UIImage? {
        memory.object(forKey: Self.key(for: url) as NSString)
    }

    /// The shrunk photo: from memory, else from disk, else downloaded (and
    /// then kept). nil if it can't be had (e.g. an expired link); asking
    /// again with a newer link tries again.
    func image(for url: URL) async -> UIImage? {
        let key = Self.key(for: url)
        if let image = memory.object(forKey: key as NSString) { return image }
        let task: Task<UIImage?, Never> = lock.withLock {
            if let running = inFlight[key] { return running }
            let task = Task.detached(priority: .userInitiated) { [self] in
                await self.load(url: url, key: key)
            }
            inFlight[key] = task
            return task
        }
        let image = await task.value
        lock.withLock { inFlight[key] = nil }
        return image
    }

    /// Fetches the photos in the background, so Story has them when it opens.
    func prefetch(_ urls: [URL]) {
        for url in urls where cachedImage(for: url) == nil {
            Task.detached(priority: .utility) { [self] in _ = await self.image(for: url) }
        }
    }

    private func load(url: URL, key: String) async -> UIImage? {
        let installation = await MainActor.run { try? InstallationID.current() }
        let file = installation.flatMap { Self.file(for: key, installation: $0) }
        if let file, let data = try? Data(contentsOf: file), let image = Self.downsample(data) {
            remember(image, key: key)
            Self.log.debug("photo from disk")
            return image
        }
        Self.log.debug("photo downloading")
        guard let data = try? await APIClient.shared.downloadPhoto(from: url),
              let image = Self.downsample(data) else { return nil }
        remember(image, key: key)
        if let file {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
        return image
    }

    private func remember(_ image: UIImage, key: String) {
        memory.setObject(image, forKey: key as NSString)
        lock.withLock { _ = memoryKeys.insert(key) }
    }

    // MARK: Cleanup

    /// Keeps only these photos (the memories the server just returned) and
    /// deletes every other cached copy: other files of this installation
    /// (e.g. a deleted memory's, or a rehearsal photo removed by a reset) and
    /// any other installation's folder. Call it only with a list from a
    /// successful load, never from offline or saved data.
    func keepOnly(_ urls: [URL], installation: UUID) {
        let keep = Set(urls.map(Self.key(for:)))
        let evict = lock.withLock { () -> Set<String> in
            let gone = memoryKeys.subtracting(keep)
            memoryKeys.subtract(gone)
            return gone
        }
        evict.forEach { memory.removeObject(forKey: $0 as NSString) }
        Task.detached(priority: .utility) {
            Self.pruneFiles(keeping: keep, installation: installation)
        }
    }

    /// Deletes every cached photo (memory and disk), for when this
    /// installation's journey was reset on the server.
    func removeAll() {
        lock.withLock { memoryKeys.removeAll() }
        memory.removeAllObjects()
        Task.detached(priority: .utility) {
            guard let root = Self.root else { return }
            try? FileManager.default.removeItem(at: root)
            Self.log.debug("photo cache cleared")
        }
    }

    /// The file part of `keepOnly`, testable with any folder.
    @discardableResult
    static func pruneFiles(keeping keep: Set<String>, installation: UUID, root: URL? = root,
                           fileManager: FileManager = .default) -> [String] {
        guard let root, let folders = try? fileManager.contentsOfDirectory(atPath: root.path) else { return [] }
        var removed: [String] = []
        for folder in folders {
            let folderURL = root.appending(path: folder)
            guard folder == installation.uuidString else {
                if (try? fileManager.removeItem(at: folderURL)) != nil { removed.append(folder + "/") }
                continue
            }
            for name in (try? fileManager.contentsOfDirectory(atPath: folderURL.path)) ?? []
            where !keep.contains((name as NSString).deletingPathExtension) {
                if (try? fileManager.removeItem(at: folderURL.appending(path: name))) != nil { removed.append(name) }
            }
        }
        if !removed.isEmpty { log.debug("photo cache pruned \(removed.count) item(s)") }
        return removed
    }

    /// Caches/ScrapbookPhotos.
    static var root: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appending(path: "ScrapbookPhotos")
    }

    private static let log = Logger(subsystem: "CtrlExDelete", category: "photos")

    /// The photo's identity: its object path, the same on every temporary link.
    static func key(for url: URL) -> String {
        SHA256.hash(data: Data(url.path.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Caches/ScrapbookPhotos/<installation ID>/<key>.jpg; nil without an ID.
    private static func file(for key: String, installation: UUID) -> URL? {
        root?.appending(path: "\(installation.uuidString)/\(key).jpg")
    }

    /// Decodes the JPEG straight to a smaller bitmap (ImageIO thumbnail),
    /// just big enough for a card at `minimumPixelSize`, never enlarged.
    /// The aspect ratio is kept; the card crops it as before.
    static func downsample(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0 else { return nil }
        let scale = min(1, max(minimumPixelSize.width / width, minimumPixelSize.height / height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int((max(width, height) * scale).rounded(.up)),
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail)
    }
}
