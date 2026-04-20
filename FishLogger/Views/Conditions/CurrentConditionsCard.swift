import SwiftUI
import WeatherKit

/// Fishing-focused "right now" card. Signal order is most-actionable first:
/// pressure trend → wind → air/cloud → precip → condition prose.
struct CurrentConditionsCard: View {
    let snapshot: ConditionsSnapshot

    private var current: CurrentWeather { snapshot.bundle.current }

    /// Derive a 6h pressure trend from the hourly forecast — WeatherKit's
    /// instantaneous `pressureTrend` is coarse; the numeric delta is the
    /// pre-frontal signal anglers care about.
    private var sixHourPressureDelta: Double? {
        let hours = Array(snapshot.bundle.hourly)
        guard
            let nowHour = hours.min(by: { abs($0.date.timeIntervalSinceNow) < abs($1.date.timeIntervalSinceNow) }),
            let sixAhead = hours.first(where: { $0.date.timeIntervalSince(nowHour.date) >= 5.5 * 3600 })
        else { return nil }
        let nowMb = nowHour.pressure.converted(to: .millibars).value
        let sixMb = sixAhead.pressure.converted(to: .millibars).value
        // We actually want PAST 6h, but the forecast only goes forward from
        // "now". Report forward delta as a proxy with an explicit label.
        return sixMb - nowMb
    }

    var body: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RIGHT NOW")
                            .font(.fieldLabel)
                            .foregroundStyle(Color.inkFaded)
                        Text(current.condition.description)
                            .font(.species)
                            .foregroundStyle(Color.ink)
                        Text("Nearest station to \(snapshot.area.name) · regional reading")
                            .font(.cozyCaption)
                            .foregroundStyle(Color.inkFaded)
                    }
                    Spacer()
                    Image(systemName: current.symbolName)
                        .font(.system(size: 42))
                        .foregroundStyle(Color.sunset)
                        .symbolRenderingMode(.multicolor)
                }

                // Pressure row — headline fishing signal.
                pressureRow

                Divider().background(Color.bark.opacity(0.4))

                // Wind + air/cloud + precip.
                HStack(alignment: .top, spacing: 16) {
                    metric(
                        label: "WIND",
                        value: "\(Int(current.wind.speed.converted(to: .kilometersPerHour).value.rounded())) km/h",
                        sub: windDirectionText,
                        icon: "wind"
                    )
                    metric(
                        label: "AIR",
                        value: "\(tempDisplay(current.temperature))",
                        sub: "\(Int((current.cloudCover * 100).rounded()))% cloud",
                        icon: "thermometer.medium"
                    )
                    metric(
                        label: "RAIN",
                        value: "\(Int((nextSixHourPrecipChance * 100).rounded()))%",
                        sub: "next 6h",
                        icon: "cloud.rain.fill"
                    )
                }
            }
        }
    }

    private var pressureRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PRESSURE")
                .font(.fieldLabel)
                .foregroundStyle(Color.inkFaded)
            HStack(spacing: 10) {
                let trend = PressureTrend(current.pressureTrend)
                Image(systemName: trend.symbolName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(trendColor(trend))
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(pressureDisplay)
                            .font(.statValue.weight(.semibold))
                            .foregroundStyle(Color.ink)
                        Text("mb")
                            .font(.cozyCaption)
                            .foregroundStyle(Color.inkFaded)
                    }
                    Text(pressureSubtitle(trend: trend))
                        .font(.cozyCaption)
                        .foregroundStyle(Color.inkFaded)
                }
                Spacer()
            }
        }
    }

    private func pressureSubtitle(trend: PressureTrend) -> String {
        let base = trend.display
        guard let delta = sixHourPressureDelta else { return base }
        let sign = delta >= 0 ? "+" : ""
        return "\(base) · \(sign)\(String(format: "%.1f", delta)) mb next 6h"
    }

    private var pressureDisplay: String {
        let value = current.pressure.converted(to: .millibars).value
        return String(format: "%.1f", value)
    }

    private func trendColor(_ trend: PressureTrend) -> Color {
        switch trend {
        case .falling: return Color.sunset
        case .rising:  return Color.inkFaded
        case .steady:  return Color.inkFaded
        }
    }

    private var windDirectionText: String {
        let deg = current.wind.direction.converted(to: .degrees).value
        return compass(for: deg)
    }

    private func compass(for degrees: Double) -> String {
        let dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]
        let idx = Int(((degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)) / 22.5 + 0.5) % 16
        return dirs[idx]
    }

    private func tempDisplay(_ temp: Measurement<UnitTemperature>) -> String {
        let f = temp.converted(to: .fahrenheit).value
        return "\(Int(f.rounded()))°F"
    }

    private var nextSixHourPrecipChance: Double {
        let hours = Array(snapshot.bundle.hourly.prefix(6))
        guard !hours.isEmpty else { return 0 }
        return hours.map { $0.precipitationChance }.max() ?? 0
    }

    private func metric(label: String, value: String, sub: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.inkFaded)
                Text(label)
                    .font(.fieldLabel)
                    .foregroundStyle(Color.inkFaded)
            }
            Text(value)
                .font(.species)
                .foregroundStyle(Color.ink)
            Text(sub)
                .font(.cozyCaption)
                .foregroundStyle(Color.inkFaded)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
