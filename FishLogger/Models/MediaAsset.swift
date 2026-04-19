import Foundation
import SwiftData

@Model
final class MediaAsset {
    var id: UUID
    var relativePath: String
    var kindRaw: String
    var createdAt: Date
    /// Seconds into the video to use for the thumbnail. Ignored for photos.
    var thumbnailTimeSeconds: Double = 0.5

    var owner: Catch?

    init(relativePath: String, kind: MediaKind, createdAt: Date = .now, thumbnailTimeSeconds: Double = 0.5) {
        self.id = UUID()
        self.relativePath = relativePath
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
        self.thumbnailTimeSeconds = thumbnailTimeSeconds
    }

    var kind: MediaKind {
        MediaKind(rawValue: kindRaw) ?? .photo
    }

    var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(relativePath)
    }
}
