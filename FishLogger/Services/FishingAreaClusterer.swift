import Foundation
import CoreLocation

/// Groups spots into one or more "fishing areas" by geographic proximity.
/// A pond produces multiple 100-m catch spots that all belong to one area;
/// a separate lake across town is a different area.
struct FishingArea: Identifiable, Hashable {
    let id: UUID
    let centroid: CLLocationCoordinate2D
    let spots: [Spot]
    let name: String

    static func == (lhs: FishingArea, rhs: FishingArea) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum FishingAreaClusterer {

    /// 2 km: large enough to keep a single pond together (existing spot
    /// clusters are 100 m), small enough to split a neighboring lake into its
    /// own area.
    static let defaultThresholdMeters: Double = 2_000

    static func cluster(
        spots: [Spot],
        thresholdMeters: Double = defaultThresholdMeters
    ) -> [FishingArea] {
        guard !spots.isEmpty else { return [] }

        // Single-pass union-find. O(N²) distance checks — fine for N<50.
        var parent: [Int] = Array(0..<spots.count)

        func find(_ i: Int) -> Int {
            var root = i
            while parent[root] != root { root = parent[root] }
            // Path compression.
            var cur = i
            while parent[cur] != root {
                let next = parent[cur]
                parent[cur] = root
                cur = next
            }
            return root
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }

        for i in 0..<spots.count {
            let li = CLLocation(latitude: spots[i].centerLat, longitude: spots[i].centerLon)
            for j in (i + 1)..<spots.count {
                let lj = CLLocation(latitude: spots[j].centerLat, longitude: spots[j].centerLon)
                if li.distance(from: lj) <= thresholdMeters {
                    union(i, j)
                }
            }
        }

        var groups: [Int: [Spot]] = [:]
        for i in 0..<spots.count {
            groups[find(i), default: []].append(spots[i])
        }

        return groups.values.map { group -> FishingArea in
            let centroid = centroid(of: group)
            let name = areaName(for: group)
            // Deterministic id so SwiftUI doesn't churn on re-cluster.
            let id = deterministicID(for: group)
            return FishingArea(id: id, centroid: centroid, spots: group, name: name)
        }
        .sorted { $0.spots.count > $1.spots.count }
    }

    private static func centroid(of spots: [Spot]) -> CLLocationCoordinate2D {
        let n = Double(spots.count)
        let lat = spots.reduce(0.0) { $0 + $1.centerLat } / n
        let lon = spots.reduce(0.0) { $0 + $1.centerLon } / n
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private static func areaName(for spots: [Spot]) -> String {
        if spots.count == 1 { return spots[0].name }
        // Pick the spot that anchors the most catches.
        let anchor = spots.max(by: { $0.catches.count < $1.catches.count }) ?? spots[0]
        return "\(anchor.name) area"
    }

    private static func deterministicID(for spots: [Spot]) -> UUID {
        // Hash the sorted spot-id strings into the first 16 bytes of a UUID so
        // the area's identity is stable across re-clusters with the same input.
        let joined = spots.map { $0.id.uuidString }.sorted().joined(separator: "|")
        var hasher = Hasher()
        hasher.combine(joined)
        let h = hasher.finalize()
        var bytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: h) { src in
            for i in 0..<min(src.count, 16) { bytes[i] = src[i] }
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
