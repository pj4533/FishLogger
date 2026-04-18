import Foundation
import ImageIO
import CoreLocation
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

enum PhotoMetadataExtractor {
    /// Extracts EXIF capture date and GPS coordinate from a `PhotosPickerItem` if either
    /// is present in the image's metadata. Video items return `nil`.
    static func extract(from item: PhotosPickerItem) async -> PhotoMetadata? {
        guard itemLooksLikePhoto(item) else { return nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return extract(from: data)
    }

    static func extract(from data: Data) -> PhotoMetadata? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }

        let date = parseDate(from: properties)
        let coord = parseCoordinate(from: properties)

        let meta = PhotoMetadata(capturedAt: date, coordinate: coord)
        return meta.isEmpty ? nil : meta
    }

    // MARK: - Private

    private static func itemLooksLikePhoto(_ item: PhotosPickerItem) -> Bool {
        let imageTypes: [UTType] = [.image, .heic, .jpeg, .png]
        for t in imageTypes {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: t) }) { return true }
        }
        return false
    }

    private static func parseDate(from properties: [CFString: Any]) -> Date? {
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

    private static func parseCoordinate(from properties: [CFString: Any]) -> CLLocationCoordinate2D? {
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
        // Photos without GPS often report (0,0) — skip that common garbage value.
        if lat == 0 && lon == 0 { return nil }

        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
