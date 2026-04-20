import Foundation
import WeatherKit

/// Ranks the best fishing hour across a multi-day hourly forecast using the
/// signals research identifies as actionable: falling pressure, cloud cover,
/// proximity to sunrise/sunset, solunar majors/minors, low wind, low precip.
///
/// Deliberately rule-based. The LLM step later will replace or augment this
/// with reasoning grounded in the user's own catch history.
struct BestFishingWindow {
    let interval: DateInterval
    let score: Double
    /// Human-readable phrases describing why this window scored well.
    let rationale: [String]
}

struct ScoredHour {
    let date: Date
    let score: Double
    let reasons: [String]
}

enum ConditionsScorer {

    /// Minimum summed 2-hour score before we surface a window. Keeps us from
    /// promoting "the least bad slot" when nothing is actually signal-rich.
    private static let surfaceThreshold: Double = 2.0

    static func bestWindow(
        hours: [HourWeather],
        dailyByDate: [Date: DayWeather],
        solunarByDate: [Date: Solunar],
        calendar: Calendar = .current
    ) -> BestFishingWindow? {
        // Score only daylight hours — "best time to fish" by definition doesn't
        // include pitch dark, and we don't want night to leak into the
        // rationale of an otherwise valid morning window.
        let scored: [ScoredHour] = hours.compactMap { hour in
            score(
                hour: hour,
                dailyByDate: dailyByDate,
                solunarByDate: solunarByDate,
                calendar: calendar
            )
        }

        guard scored.count >= 2 else { return nil }

        // Only evaluate pairs of truly consecutive hours (skip the gap across
        // dusk → next dawn). If WeatherKit returns hours on the hour, gaps
        // should be exactly 3600 s.
        var best: (startIdx: Int, score: Double)? = nil
        for i in 0..<(scored.count - 1) {
            let gap = scored[i + 1].date.timeIntervalSince(scored[i].date)
            guard abs(gap - 3600) < 60 else { continue }
            let pair = scored[i].score + scored[i + 1].score
            if best == nil || pair > best!.score {
                best = (i, pair)
            }
        }

        guard
            let bestIdx = best?.startIdx,
            let bestScore = best?.score,
            bestScore >= surfaceThreshold
        else {
            return nil
        }

        let start = scored[bestIdx].date
        let end = scored[bestIdx + 1].date.addingTimeInterval(3600)
        let rationale = (scored[bestIdx].reasons + scored[bestIdx + 1].reasons).unique()

        return BestFishingWindow(
            interval: DateInterval(start: start, end: end),
            score: bestScore,
            rationale: rationale
        )
    }

    /// Returns a ScoredHour for a daylight hour, or nil if the hour falls
    /// outside the daylight window ±30 minutes.
    static func score(
        hour: HourWeather,
        dailyByDate: [Date: DayWeather],
        solunarByDate: [Date: Solunar],
        calendar: Calendar = .current
    ) -> ScoredHour? {
        let solunar = findSolunar(for: hour.date, in: solunarByDate, calendar: calendar)
        let daily = findDaily(for: hour.date, in: dailyByDate, calendar: calendar)
        let sunrise = solunar?.sunrise ?? daily?.sun.sunrise
        let sunset  = solunar?.sunset  ?? daily?.sun.sunset

        // If we can't determine daylight bounds at all, assume daylight — the
        // hour might still usefully contribute to a best window. This lets the
        // feature degrade gracefully when WeatherKit / SunCalc don't agree on
        // a day key.
        if let sunrise, let sunset {
            let daylightStart = sunrise.addingTimeInterval(-30 * 60)
            let daylightEnd = sunset.addingTimeInterval(30 * 60)
            guard hour.date >= daylightStart && hour.date <= daylightEnd else {
                return nil
            }
        }

        var s: Double = 0
        var reasons: [String] = []

        // Cloud cover — overcast extends feeding windows.
        if hour.cloudCover > 0.6 {
            s += 2
            reasons.append("overcast")
        }

        // Pressure trend — WeatherKit instantaneous trend as a quick signal.
        switch hour.pressureTrend {
        case .falling:
            s += 2
            reasons.append("falling pressure")
        case .rising:
            s -= 0.5
        default: break
        }

        // Wind — a little surface chop helps, but above 25 km/h it's a problem.
        let windKmh = hour.wind.speed.converted(to: .kilometersPerHour).value
        if windKmh > 25 {
            s -= 2
            reasons.append("high wind")
        } else if windKmh > 8 {
            s += 0.5
        }

        // Precipitation — light is fine, heavy kills the day.
        if hour.precipitationChance > 0.7 {
            s -= 1
            reasons.append("heavy rain likely")
        }

        // Solunar major / minor bonus.
        if let solunar {
            if solunar.majors.contains(where: { $0.contains(hour.date) }) {
                s += 2
                reasons.append("solunar major")
            } else if solunar.minors.contains(where: { $0.contains(hour.date) }) {
                s += 1
                reasons.append("solunar minor")
            }
        }

        // Dawn / dusk bonus (±1 h). Stacks with solunar if applicable.
        if let sunrise, abs(hour.date.timeIntervalSince(sunrise)) <= 3600 {
            s += 2
            reasons.append("dawn")
        } else if let sunset, abs(hour.date.timeIntervalSince(sunset)) <= 3600 {
            s += 2
            reasons.append("dusk")
        }

        return ScoredHour(date: hour.date, score: s, reasons: reasons)
    }

    /// Forgiving lookup — try exact `startOfDay` key first, then fall back to
    /// `isDate(_:inSameDayAs:)` scan so a mismatch between our day keys and
    /// WeatherKit's `DayWeather.date` timezone handling doesn't drop the
    /// lookup silently.
    private static func findSolunar(
        for date: Date,
        in dict: [Date: Solunar],
        calendar: Calendar
    ) -> Solunar? {
        let exact = calendar.startOfDay(for: date)
        if let hit = dict[exact] { return hit }
        return dict.first(where: { calendar.isDate($0.key, inSameDayAs: date) })?.value
    }

    private static func findDaily(
        for date: Date,
        in dict: [Date: DayWeather],
        calendar: Calendar
    ) -> DayWeather? {
        let exact = calendar.startOfDay(for: date)
        if let hit = dict[exact] { return hit }
        return dict.first(where: { calendar.isDate($0.key, inSameDayAs: date) })?.value
    }
}

private extension Array where Element == String {
    func unique() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
