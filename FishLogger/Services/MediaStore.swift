import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum MediaStoreError: Error {
    case unsupportedType
    case writeFailed
}

enum MediaStore {
    private static let directoryName = "Media"

    private static func mediaDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent(directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func save(_ item: PhotosPickerItem) async throws -> MediaAsset {
        let (data, kind, ext) = try await load(from: item)
        let dir = try mediaDirectory()
        let filename = "\(UUID().uuidString).\(ext)"
        let fileURL = dir.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw MediaStoreError.writeFailed
        }
        let relativePath = "\(directoryName)/\(filename)"
        return MediaAsset(relativePath: relativePath, kind: kind)
    }

    static func delete(_ asset: MediaAsset) {
        let url = asset.url
        try? FileManager.default.removeItem(at: url)
    }

    private static func load(from item: PhotosPickerItem) async throws -> (Data, MediaKind, String) {
        let supportedImages: [UTType] = [.heic, .jpeg, .png]
        let supportedVideos: [UTType] = [.quickTimeMovie, .mpeg4Movie, .movie]

        for type in supportedImages {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: type) }),
               let data = try? await item.loadTransferable(type: Data.self) {
                return (data, .photo, type.preferredFilenameExtension ?? "jpg")
            }
        }
        for type in supportedVideos {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: type) }),
               let data = try? await item.loadTransferable(type: Data.self) {
                return (data, .video, type.preferredFilenameExtension ?? "mov")
            }
        }
        if let data = try? await item.loadTransferable(type: Data.self) {
            return (data, .photo, "bin")
        }
        throw MediaStoreError.unsupportedType
    }
}
