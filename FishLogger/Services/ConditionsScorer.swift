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
    let rationale: [String]
}

struct ScoredHour {
    let date: Date
    let score: Double
    let reasons: [String]
}

enum ConditionsScorer {

    static func bestWindow(
        hours: [HourWeather],
        dailyByDate: [Date: DayWeather],
        solunarByDate: [Date: Solunar],
        calendar: Calendar = .current
    ) -> BestFishingWindow? {
        guard !hours.isEmpty else { return nil }

        let scored = hours.map { score(hour: $0, dailyByDate: dailyByDate, solunarByDate: solunarByDate, calendar: calendar) }

        // Find the best 2-hour consecutive window.
        var best: (index: Int, score: Double)? = nil
        for i in 0..<(scored.count - 1) {
            let pair = scored[i].score + scored[i + 1].score
            if best == nil || pair > best!.score {
                best = (i, pair)
            }
        }

        guard let bestIdx = best?.index else { return nil }
        let start = scored[bestIdx].date
        let end = scored[bestIdx + 1].date.addingTimeInterval(3600)
        let rationale = (scored[bestIdx].reasons + scored[bestIdx + 1].reasons).unique()

        return BestFishingWindow(
            interval: DateInterval(start: start, end: end),
            score: best!.score,
            rationale: rationale
        )
    }

    static func score(
        hour: HourWeather,
        dailyByDate: [Date: DayWeather],
        solunarByDate: [Date: Solunar],
        calendar: Calendar = .current
    ) -> ScoredHour {
        var s: Double = 0
        var reasons: [String] = []

        let day = calendar.startOfDay(for: hour.date)
        let solunar = solunarByDate[day]

        // Daylight gate — we only score daylight hours for "best window".
        // Dawn/dusk already get their own bonus below.
        let daily = dailyByDate[day]
        let sunrise = solunar?.sunrise ?? daily?.sun.sunrise
        let sunset = solunar?.sunset ?? daily?.sun.sunset
        let isDaylight: Bool = {
            guard let sunrise, let sunset else { return true }
            return hour.date >= sunrise.addingTimeInterval(-30 * 60)
                && hour.date <= sunset.addingTimeInterval(30 * 60)
        }()
        if !isDaylight {
            return ScoredHour(date: hour.date, score: -5, reasons: ["night"])
        }

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

        // Wind — surface chop helps, but above 25 km/h it's a problem.
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

        // Dawn / dusk bonus (±1h). Doubles when stacked with a solunar window.
        if let sunrise, abs(hour.date.timeIntervalSince(sunrise)) <= 3600 {
            s += 2
            reasons.append("dawn")
        } else if let sunset, abs(hour.date.timeIntervalSince(sunset)) <= 3600 {
            s += 2
            reasons.append("dusk")
        }

        return ScoredHour(date: hour.date, score: s, reasons: reasons)
    }
}

private extension Array where Element == String {
    func unique() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
