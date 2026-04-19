import Foundation
import ImageIO
import CoreLocation
import CoreTransferable
import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct PhotoMetadata: Equatable {
    var capturedAt: Date?
    var coordinate: CLLocationCoordinate2D?

    var isEmpty: Bool { capturedAt == nil && coordinate == nil }

    static func == (lhs: PhotoMetadata, rhs: PhotoMetadata) -> Bool {
        lhs.capturedAt == rhs.capturedAt
            && lhs.coordinate?.latitude == rhs.coordinate?.latitude
            && lhs.coordinate?.longitude == rhs.coordinate?.longitude
    }
}

/// Transferable wrapper that materializes a `PhotosPickerItem` video as a
/// file URL inside the temp directory. We delete the file after we're done
/// reading metadata from it.
struct TransferableMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dest = URL.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return Self(url: dest)
        }
    }
}

enum PhotoMetadataExtractor {
    /// Extracts capture date and GPS coordinate from a `PhotosPickerItem`
    /// (image or video). Returns `nil` if neither can be determined.
    static func extract(from item: PhotosPickerItem) async -> PhotoMetadata? {
        if itemLooksLikePhoto(item) {
            return await extractImage(from: item)
        }
        if itemLooksLikeVideo(item) {
            return await extractVideo(from: item)
        }
        return nil
    }

    static func extract(from data: Data) -> PhotoMetadata? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }

        let date = parseImageDate(from: properties)
        let coord = parseImageCoordinate(from: properties)

        let meta = PhotoMetadata(capturedAt: date, coordinate: coord)
        return meta.isEmpty ? nil : meta
    }

    // MARK: - Image

    private static func extractImage(from item: PhotosPickerItem) async -> PhotoMetadata? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return extract(from: data)
    }

    private static func itemLooksLikePhoto(_ item: PhotosPickerItem) -> Bool {
        let imageTypes: [UTType] = [.image, .heic, .jpeg, .png]
        for t in imageTypes {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: t) }) { return true }
        }
        return false
    }

    private static func parseImageDate(from properties: [CFString: Any]) -> Date? {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (exif?[kCGImagePropertyExifDateTimeDigitized] as? String)
            ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String)

        guard let raw else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let d = formatter.date(from: raw) { return d }

        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: raw)
    }

    private static func parseImageCoordinate(from properties: [CFString: Any]) -> CLLocationCoordinate2D? {
        guard let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] else { return nil }
        guard let latNumber = gps[kCGImagePropertyGPSLatitude] as? NSNumber,
              let lonNumber = gps[kCGImagePropertyGPSLongitude] as? NSNumber else { return nil }

        var lat = latNumber.doubleValue
        var lon = lonNumber.doubleValue

        if let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String, latRef.uppercased() == "S" {
            lat = -lat
        }
        if let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String, lonRef.uppercased() == "W" {
            lon = -lon
        }

        guard CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)) else {
            return nil
        }
        if lat == 0 && lon == 0 { return nil }

        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // MARK: - Video

    private static func extractVideo(from item: PhotosPickerItem) async -> PhotoMetadata? {
        guard let movie = try? await item.loadTransferable(type: TransferableMovie.self) else { return nil }
        defer { try? FileManager.default.removeItem(at: movie.url) }
        return await extractVideoMetadata(from: movie.url)
    }

    static func extractVideoMetadata(from url: URL) async -> PhotoMetadata? {
        let asset = AVURLAsset(url: url)

        var date: Date?
        var coord: CLLocationCoordinate2D?

        // Common metadata: creation date
        if let commonMetadata = try? await asset.load(.commonMetadata) {
            for item in commonMetadata where item.commonKey == .commonKeyCreationDate {
                if let d = try? await item.load(.dateValue) { date = d; break }
                if let s = try? await item.load(.stringValue), let parsed = parseISODate(s) {
                    date = parsed; break
                }
            }
        }

        // Format-specific metadata: QuickTime GPS + creation-date fallback
        let formats = (try? await asset.load(.availableMetadataFormats)) ?? []
        for format in formats {
            guard let items = try? await asset.loadMetadata(for: format) else { continue }
            for item in items {
                if item.identifier == .quickTimeMetadataLocationISO6709,
                   coord == nil,
                   let s = try? await item.load(.stringValue) {
                    coord = parseISO6709(s)
                }
                if date == nil,
                   item.identifier == .quickTimeMetadataCreationDate {
                    if let d = try? await item.load(.dateValue) { date = d }
                    else if let s = try? await item.load(.stringValue), let parsed = parseISODate(s) {
                        date = parsed
                    }
                }
            }
        }

        let meta = PhotoMetadata(capturedAt: date, coordinate: coord)
        return meta.isEmpty ? nil : meta
    }

    private static func itemLooksLikeVideo(_ item: PhotosPickerItem) -> Bool {
        let videoTypes: [UTType] = [.movie, .quickTimeMovie, .mpeg4Movie, .video]
        for t in videoTypes {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: t) }) { return true }
        }
        return false
    }

    /// Parses ISO 6709 coordinate strings like "+40.7128-074.0060+010.000/".
    /// Extracts the first two signed decimals as latitude and longitude.
    static func parseISO6709(_ s: String) -> CLLocationCoordinate2D? {
        var nums: [Double] = []
        var buffer = ""
        func flush() {
            if !buffer.isEmpty, let d = Double(buffer) { nums.append(d) }
            buffer = ""
        }
        for ch in s {
            if ch == "+" || ch == "-" {
                flush()
                buffer = String(ch)
            } else if ch.isNumber || ch == "." {
                buffer.append(ch)
            } else {
                flush()
            }
        }
        flush()
        guard nums.count >= 2 else { return nil }
        let lat = nums[0]
        let lon = nums[1]
        if lat == 0 && lon == 0 { return nil }
        guard CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private static func parseISODate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: s)
    }
}
