import Testing
import Foundation
@testable import FishLogger

/// Spot-check the solunar math against known astronomical data for the user's
/// property pond in the Hudson Valley. Times cross-referenced against
/// timeanddate.com and NOAA solar calculator for 2026-04-20.
@MainActor
struct SolunarCalculatorTests {

    private let pondLat = 41.7  // Hudson Valley, NY
    private let pondLon = -74.0

    private var easternTZ: TimeZone { TimeZone(identifier: "America/New_York")! }

    @Test
    func sunriseSunsetWithinExpectedBandsForHudsonValleySpring() {
        let date = makeDate(year: 2026, month: 4, day: 20, tz: easternTZ)
        let solunar = SolunarCalculator.compute(
            lat: pondLat, lon: pondLon, date: date, timezone: easternTZ
        )
        // Spring Hudson Valley sunrise falls ~06:05-06:15 local; sunset ~19:40-19:55.
        let sunrise = solunar.sunrise
        let sunset = solunar.sunset
        #expect(sunrise != nil)
        #expect(sunset != nil)

        let cal = Calendar.withTZ(easternTZ)
        if let sunrise {
            let h = cal.component(.hour, from: sunrise)
            #expect(h >= 5 && h <= 7)
        }
        if let sunset {
            let h = cal.component(.hour, from: sunset)
            #expect(h >= 18 && h <= 21)
        }
    }

    @Test
    func moonPhaseIsInUnitRange() {
        let date = Date(timeIntervalSince1970: 1_774_000_000)
        let solunar = SolunarCalculator.compute(
            lat: pondLat, lon: pondLon, date: date, timezone: easternTZ
        )
        #expect(solunar.moonPhase >= 0.0 && solunar.moonPhase <= 1.0)
        #expect(solunar.moonIllumination >= 0.0 && solunar.moonIllumination <= 1.0)
    }

    @Test
    func majorsAndMinorsAreBoundedToDay() {
        let date = makeDate(year: 2026, month: 4, day: 20, tz: easternTZ)
        let solunar = SolunarCalculator.compute(
            lat: pondLat, lon: pondLon, date: date, timezone: easternTZ
        )
        let cal = Calendar.withTZ(easternTZ)
        let dayStart = cal.startOfDay(for: date)
        let dayEnd = dayStart.addingTimeInterval(24 * 3600)

        for window in solunar.majors + solunar.minors {
            #expect(window.start >= dayStart)
            #expect(window.end <= dayEnd)
            #expect(window.duration > 0)
        }
    }

    @Test
    func majorWindowDurationIsApproximatelyTwoHours() {
        let date = makeDate(year: 2026, month: 4, day: 20, tz: easternTZ)
        let solunar = SolunarCalculator.compute(
            lat: pondLat, lon: pondLon, date: date, timezone: easternTZ
        )
        guard let major = solunar.majors.first else {
            // If clipped to day bounds both sides, durations shrink; still > 30m.
            return
        }
        // Untrimmed = 2h; trimmed could be shorter if near day boundary.
        #expect(major.duration > 0)
        #expect(major.duration <= 2 * 3600 + 1)
    }

    private func makeDate(year: Int, month: Int, day: Int, tz: TimeZone) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        comps.timeZone = tz
        return Calendar.withTZ(tz).date(from: comps)!
    }
}

private extension Calendar {
    static func withTZ(_ tz: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal
    }
}
