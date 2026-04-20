import Foundation

/// Pre-computed solunar information for a given place and local calendar day.
/// Majors / minors follow the standard "transit & opposite transit" (majors,
/// ~2 h each) and "moonrise & moonset" (minors, ~1 h each) convention.
struct Solunar {
    let sunrise: Date?
    let sunset: Date?
    let moonrise: Date?
    let moonset: Date?
    /// 0.0–1.0 phase (0=new, 0.5=full).
    let moonPhase: Double
    /// 0.0–1.0 fraction of visible disk illuminated.
    let moonIllumination: Double
    /// 1–2 major windows of ~2 hours, centered on lunar transit / anti-transit.
    let majors: [DateInterval]
    /// 1–2 minor windows of ~1 hour, centered on moonrise / moonset.
    let minors: [DateInterval]
}

enum SolunarCalculator {

    /// Window half-widths. Majors ~2h total (±1h around center), minors ~1h (±30m).
    private static let majorHalfWidth: TimeInterval = 60 * 60
    private static let minorHalfWidth: TimeInterval = 30 * 60

    /// Mean synodic lunar day is ~24h50m; opposite transit = transit + 12h25m.
    private static let antiTransitOffset: TimeInterval = 12 * 3600 + 25 * 60

    static func compute(
        lat: Double,
        lon: Double,
        date: Date,
        timezone: TimeZone = .current
    ) -> Solunar {
        let sun = SunCalc.sunTimes(date: date, lat: lat, lon: lon)
        let moon = SunCalc.moonTimes(date: date, lat: lat, lon: lon, timezone: timezone)
        let illum = SunCalc.moonIllumination(date: date)
        let transit = SunCalc.moonTransit(date: date, lat: lat, lon: lon, timezone: timezone)

        let dayBounds = localDayBounds(date: date, timezone: timezone)

        let majors = buildMajors(transit: transit, bounds: dayBounds)
        let minors = buildMinors(rise: moon.rise, set: moon.set, bounds: dayBounds)

        return Solunar(
            sunrise: sun.sunrise,
            sunset: sun.sunset,
            moonrise: moon.rise,
            moonset: moon.set,
            moonPhase: illum.phase,
            moonIllumination: illum.fraction,
            majors: majors,
            minors: minors
        )
    }

    private static func localDayBounds(date: Date, timezone: TimeZone) -> DateInterval {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let start = cal.startOfDay(for: date)
        let end = start.addingTimeInterval(24 * 3600)
        return DateInterval(start: start, end: end)
    }

    private static func buildMajors(transit: Date?, bounds: DateInterval) -> [DateInterval] {
        guard let transit else { return [] }
        let centers = [transit, transit.addingTimeInterval(antiTransitOffset),
                       transit.addingTimeInterval(-antiTransitOffset)]
        return centers
            .map { DateInterval(start: $0.addingTimeInterval(-majorHalfWidth),
                                end:   $0.addingTimeInterval(+majorHalfWidth)) }
            .compactMap { clipped($0, to: bounds) }
            .removingDuplicatesByStart()
    }

    private static func buildMinors(rise: Date?, set: Date?, bounds: DateInterval) -> [DateInterval] {
        [rise, set]
            .compactMap { $0 }
            .map { DateInterval(start: $0.addingTimeInterval(-minorHalfWidth),
                                end:   $0.addingTimeInterval(+minorHalfWidth)) }
            .compactMap { clipped($0, to: bounds) }
    }

    private static func clipped(_ interval: DateInterval, to bounds: DateInterval) -> DateInterval? {
        let start = max(interval.start, bounds.start)
        let end = min(interval.end, bounds.end)
        guard end > start else { return nil }
        return DateInterval(start: start, end: end)
    }
}

private extension Array where Element == DateInterval {
    func removingDuplicatesByStart() -> [DateInterval] {
        var seen = Set<TimeInterval>()
        return filter { interval in
            let key = interval.start.timeIntervalSinceReferenceDate.rounded()
            return seen.insert(key).inserted
        }
    }
}
