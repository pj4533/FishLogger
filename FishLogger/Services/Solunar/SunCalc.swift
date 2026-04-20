// Solar and lunar position math.
// Formulas adapted from mourner/suncalc (MIT, Vladimir Agafonkin),
// itself based on Meeus' "Astronomical Algorithms" and Astronomy Answers.
// Ported inline to avoid an SPM dependency for ~200 lines of astronomy math.

import Foundation

enum SunCalc {

    // MARK: Public API

    struct SunTimes {
        let sunrise: Date?
        let sunset: Date?
    }

    struct MoonTimes {
        let rise: Date?
        let set: Date?
        /// Moon is above the horizon for the entire period.
        let alwaysUp: Bool
        /// Moon is below the horizon for the entire period.
        let alwaysDown: Bool
    }

    struct MoonIllumination {
        /// 0.0–1.0 fraction of visible disk illuminated.
        let fraction: Double
        /// 0.0–1.0 phase: 0=new, 0.25=first quarter, 0.5=full, 0.75=last quarter.
        let phase: Double
        let angle: Double
    }

    /// Sunrise (solar altitude −0.833°) and sunset on the local day containing `date`.
    static func sunTimes(date: Date, lat: Double, lon: Double) -> SunTimes {
        let lw = rad * -lon
        let phi = rad * lat
        let d = toDays(date)
        let n = julianCycle(d: d, lw: lw)
        let ds = approxTransit(Ht: 0, lw: lw, n: n)

        let M = solarMeanAnomaly(d: ds)
        let L = eclipticLongitude(M: M)
        let dec = declination(L: L, B: 0)

        let riseJ = getSetJ(h: rad * -0.833, lw: lw, phi: phi, dec: dec, n: n, M: M, L: L, rising: true)
        let setJ = getSetJ(h: rad * -0.833, lw: lw, phi: phi, dec: dec, n: n, M: M, L: L, rising: false)

        return SunTimes(
            sunrise: riseJ.isNaN ? nil : fromJulian(riseJ),
            sunset: setJ.isNaN ? nil : fromJulian(setJ)
        )
    }

    /// Moonrise / moonset on the local day containing `date` (24h window starting local midnight).
    static func moonTimes(date: Date, lat: Double, lon: Double, timezone: TimeZone = .current) -> MoonTimes {
        let startOfDay = Self.startOfDay(date: date, timezone: timezone)
        var rise: Double?
        var set: Double?
        var ye: Double = 0

        var h0 = moonAltitude(date: startOfDay, lat: lat, lon: lon) - rad * 0.133

        var i = 1.0
        while i <= 24 {
            let h1 = moonAltitude(date: startOfDay.addingTimeInterval(i * 3600), lat: lat, lon: lon) - rad * 0.133
            let h2 = moonAltitude(date: startOfDay.addingTimeInterval((i + 1) * 3600), lat: lat, lon: lon) - rad * 0.133

            let a = (h0 + h2) / 2 - h1
            let b = (h2 - h0) / 2
            let xe = -b / (2 * a)
            ye = (a * xe + b) * xe + h1
            let d = b * b - 4 * a * h1
            var roots = 0
            var x1: Double = 0
            var x2: Double = 0

            if d >= 0 {
                let dx = sqrt(d) / (abs(a) * 2)
                x1 = xe - dx
                x2 = xe + dx
                if abs(x1) <= 1 { roots += 1 }
                if abs(x2) <= 1 { roots += 1 }
                if x1 < -1 { x1 = x2 }
            }

            if roots == 1 {
                if h0 < 0 { rise = i + x1 } else { set = i + x1 }
            } else if roots == 2 {
                rise = i + (ye < 0 ? x2 : x1)
                set = i + (ye < 0 ? x1 : x2)
            }

            if rise != nil && set != nil { break }
            h0 = h2
            i += 2
        }

        let riseDate = rise.map { startOfDay.addingTimeInterval($0 * 3600) }
        let setDate = set.map { startOfDay.addingTimeInterval($0 * 3600) }

        return MoonTimes(
            rise: riseDate,
            set: setDate,
            alwaysUp: rise == nil && set == nil && ye > 0,
            alwaysDown: rise == nil && set == nil && ye <= 0
        )
    }

    /// Upper lunar transit (moon crosses meridian overhead) on the local day containing `date`.
    /// Returns nil if no transit falls within the day.
    static func moonTransit(date: Date, lat: Double, lon: Double, timezone: TimeZone = .current) -> Date? {
        // Upper transit ~ when local hour angle of moon = 0.
        // Scan the day in 15-min steps, pick the minimum of |hourAngle| within the day.
        let startOfDay = Self.startOfDay(date: date, timezone: timezone)
        var bestTime: Date?
        var bestAbsHA = Double.infinity
        let step: TimeInterval = 15 * 60
        var t = startOfDay
        let end = startOfDay.addingTimeInterval(24 * 3600)
        while t < end {
            let ha = moonHourAngle(date: t, lat: lat, lon: lon)
            // normalize to [-pi, pi]
            var a = ha.truncatingRemainder(dividingBy: 2 * .pi)
            if a > .pi { a -= 2 * .pi }
            if a < -.pi { a += 2 * .pi }
            let abs_a = abs(a)
            if abs_a < bestAbsHA {
                bestAbsHA = abs_a
                bestTime = t
            }
            t = t.addingTimeInterval(step)
        }
        return bestTime
    }

    static func moonIllumination(date: Date) -> MoonIllumination {
        let d = toDays(date)
        let s = sunCoords(d: d)
        let m = moonCoords(d: d)
        let sdist: Double = 149598000
        let phi = acos(sin(s.dec) * sin(m.dec) + cos(s.dec) * cos(m.dec) * cos(s.ra - m.ra))
        let inc = atan2(sdist * sin(phi), m.dist - sdist * cos(phi))
        let angle = atan2(
            cos(s.dec) * sin(s.ra - m.ra),
            sin(s.dec) * cos(m.dec) - cos(s.dec) * sin(m.dec) * cos(s.ra - m.ra)
        )
        let phase = 0.5 + 0.5 * inc * (angle < 0 ? -1 : 1) / .pi
        return MoonIllumination(
            fraction: (1 + cos(inc)) / 2,
            phase: phase,
            angle: angle
        )
    }

    // MARK: Time conversion

    private static let rad = Double.pi / 180.0
    private static let e = rad * 23.4397
    private static let J1970: Double = 2440588
    private static let J2000: Double = 2451545
    private static let dayMs: Double = 86400
    private static let J0: Double = 0.0009

    private static func toJulian(_ date: Date) -> Double {
        date.timeIntervalSince1970 / dayMs - 0.5 + J1970
    }
    private static func fromJulian(_ j: Double) -> Date {
        Date(timeIntervalSince1970: (j + 0.5 - J1970) * dayMs)
    }
    private static func toDays(_ date: Date) -> Double {
        toJulian(date) - J2000
    }

    private static func startOfDay(date: Date, timezone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        return cal.startOfDay(for: date)
    }

    // MARK: Equatorial + observer transforms

    private static func rightAscension(L: Double, B: Double) -> Double {
        atan2(sin(L) * cos(e) - tan(B) * sin(e), cos(L))
    }
    private static func declination(L: Double, B: Double) -> Double {
        asin(sin(B) * cos(e) + cos(B) * sin(e) * sin(L))
    }
    private static func siderealTime(d: Double, lw: Double) -> Double {
        rad * (280.16 + 360.9856235 * d) - lw
    }
    private static func altitude(H: Double, phi: Double, dec: Double) -> Double {
        asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(H))
    }

    // MARK: Sun

    private static func solarMeanAnomaly(d: Double) -> Double {
        rad * (357.5291 + 0.98560028 * d)
    }
    private static func eclipticLongitude(M: Double) -> Double {
        let C = rad * (1.9148 * sin(M) + 0.02 * sin(2 * M) + 0.0003 * sin(3 * M))
        let P = rad * 102.9372
        return M + C + P + .pi
    }
    private static func sunCoords(d: Double) -> (dec: Double, ra: Double) {
        let M = solarMeanAnomaly(d: d)
        let L = eclipticLongitude(M: M)
        return (dec: declination(L: L, B: 0), ra: rightAscension(L: L, B: 0))
    }
    private static func julianCycle(d: Double, lw: Double) -> Double {
        (d - J0 - lw / (2 * .pi)).rounded()
    }
    private static func approxTransit(Ht: Double, lw: Double, n: Double) -> Double {
        J0 + (Ht + lw) / (2 * .pi) + n
    }
    private static func solarTransitJ(ds: Double, M: Double, L: Double) -> Double {
        J2000 + ds + 0.0053 * sin(M) - 0.0069 * sin(2 * L)
    }
    private static func hourAngle(h: Double, phi: Double, d: Double) -> Double {
        acos((sin(h) - sin(phi) * sin(d)) / (cos(phi) * cos(d)))
    }
    private static func getSetJ(
        h: Double, lw: Double, phi: Double, dec: Double,
        n: Double, M: Double, L: Double, rising: Bool
    ) -> Double {
        let w = hourAngle(h: h, phi: phi, d: dec)
        let a = approxTransit(Ht: rising ? -w : w, lw: lw, n: n)
        return solarTransitJ(ds: a, M: M, L: L)
    }

    // MARK: Moon

    private static func moonCoords(d: Double) -> (ra: Double, dec: Double, dist: Double) {
        let L = rad * (218.316 + 13.176396 * d)  // ecliptic longitude
        let M = rad * (134.963 + 13.064993 * d)  // mean anomaly
        let F = rad * (93.272 + 13.229350 * d)   // mean distance
        let lng = L + rad * 6.289 * sin(M)       // longitude
        let lat = rad * 5.128 * sin(F)           // latitude
        let dist = 385001 - 20905 * cos(M)       // km
        return (
            ra: rightAscension(L: lng, B: lat),
            dec: declination(L: lng, B: lat),
            dist: dist
        )
    }
    private static func moonAltitude(date: Date, lat: Double, lon: Double) -> Double {
        let lw = rad * -lon
        let phi = rad * lat
        let d = toDays(date)
        let c = moonCoords(d: d)
        let H = siderealTime(d: d, lw: lw) - c.ra
        // Atmospheric refraction correction
        var h = altitude(H: H, phi: phi, dec: c.dec)
        h += rad * 0.017 / tan(h + rad * 10.26 / (h + rad * 5.10))
        return h
    }
    private static func moonHourAngle(date: Date, lat: Double, lon: Double) -> Double {
        let lw = rad * -lon
        let d = toDays(date)
        let c = moonCoords(d: d)
        return siderealTime(d: d, lw: lw) - c.ra
    }
}
