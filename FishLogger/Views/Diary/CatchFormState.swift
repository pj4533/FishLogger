import Foundation
import SwiftUI
import PhotosUI
import CoreLocation
import Observation

@MainActor
@Observable
final class CatchFormState {
    var timestamp: Date = .now
    var location: CLLocationCoordinate2D?
    var locationAccuracy: Double?
    var pickedMedia: [PhotosPickerItem] = []
    var species: Species?
    var weightText: String = ""
    var isMeasured: Bool = true
    var baitUsed: String = ""
    var rodUsed: String = ""
    var notes: String = ""

    var isLocationRequesting: Bool = false
    var lastError: String?

    /// True once the user has manually edited the timestamp — after that,
    /// EXIF data from picked photos no longer overwrites it.
    var userEditedTimestamp: Bool = false

    /// True once the user has manually set/refreshed the location — after that,
    /// EXIF GPS from picked photos no longer overwrites it.
    var userEditedLocation: Bool = false

    /// Indicates the last auto-fill source so the UI can show a subtle badge.
    var timestampSource: ValueSource = .defaulted
    var locationSource: ValueSource = .defaulted

    enum ValueSource {
        case defaulted    // initial .now / nil
        case photo        // pulled from EXIF
        case gps          // captured from CoreLocation
        case manual       // user edited
    }

    var canSave: Bool {
        species != nil && location != nil && (Double(weightText) ?? 0) >= 0
    }

    var weightValue: Double {
        Double(weightText) ?? 0
    }

    func reset() {
        timestamp = .now
        location = nil
        locationAccuracy = nil
        pickedMedia = []
        species = nil
        weightText = ""
        isMeasured = true
        baitUsed = ""
        rodUsed = ""
        notes = ""
        lastError = nil
        userEditedTimestamp = false
        userEditedLocation = false
        timestampSource = .defaulted
        locationSource = .defaulted
    }

    func applyPhotoMetadata(_ metadata: PhotoMetadata) {
        if let d = metadata.capturedAt, !userEditedTimestamp {
            timestamp = d
            timestampSource = .photo
        }
        if let c = metadata.coordinate, !userEditedLocation {
            location = c
            locationAccuracy = nil
            locationSource = .photo
        }
    }

    /// Merges non-nil fields from a DictationParseResult. Used when dictation ships.
    func apply(_ parsed: DictationParseResult) {
        if let t = parsed.timestamp { timestamp = t }
        if let s = parsed.species { species = s }
        if let w = parsed.weight { weightText = String(w) }
        if let m = parsed.isMeasured { isMeasured = m }
        if let b = parsed.bait, !b.isEmpty { baitUsed = b }
        if let r = parsed.rod, !r.isEmpty { rodUsed = r }
        if let n = parsed.notes, !n.isEmpty { notes = n }
    }
}
