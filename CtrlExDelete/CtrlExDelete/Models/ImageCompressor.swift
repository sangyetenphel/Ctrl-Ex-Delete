import UIKit

/// Shrinks photos before upload so they're fast to send and cheap to store.
enum ImageCompressor {
    /// Longest side at most 1600px, JPEG at 70% quality (roughly 200–500 KB).
    static func jpeg(from image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.7) -> Data? {
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}