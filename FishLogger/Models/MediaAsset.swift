import Foundation
import SwiftData

@Model
final class MediaAsset {
    var id: UUID
    var relativePath: String
    var kindRaw: String
    var createdAt: Date

    var owner: Catch?

    init(relativePath: String, kind: MediaKind, createdAt: Date = .now) {
        self.id = UUID()
        self.relativePath = relativePath
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
    }

    var kind: MediaKind {
        MediaKind(rawValue: kindRaw) ?? .photo
    }

    var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(relativePath)
    }
}
