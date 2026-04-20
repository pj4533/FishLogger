import SwiftUI

/// Rendered inside CatchDetailView when a catch has successfully backfilled
/// conditions. Surfaces the fishing-signal fields + a "caught during a
/// major/minor" badge when applicable.
struct ConditionsAtCatchSection: View {
    let entry: Catch

    var body: some View {
        if entry.conditionsFetchedAt != nil {
            CozyCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("CONDITIONS AT CATCH")
                        .font(.fieldLabel)
                        .foregroundStyle(Color.inkFaded)

                    if let activeWindow = activeSolunarWindow {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.sunset)
                            Text("Caught during a solunar \(activeWindow)")
                                .font(.cozyBody.weight(.semibold))
                                .foregroundStyle(Color.ink)
                        }
                    }

                    HStack(alignment: .top, spacing: 16) {
                        pressureBlock
                        windBlock
                        airBlock
                    }

                    if entry.sunriseAt != nil || entry.sunsetAt != nil || entry.moonPhase != nil {
                        Divider().background(Color.bark.opacity(0.4))
                        sunMoonRow
                    }
                }
            }
        }
    }

    private var activeSolunarWindow: String? {
        if entry.solunarMajors.contains(where: { $0.contains(entry.timestamp) }) {
            return "major"
        }
        if entry.solunarMinors.contains(where: { $0.contains(entry.timestamp) }) {
            return "minor"
        }
        return nil
    }

    private var pressureBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let trend = entry.pressureTrend {
                    Image(systemName: trend.symbolName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(trend == .falling ? Color.sunset : Color.inkFaded)
                }
                Text("PRESSURE")
                    .font(.fieldLabel)
                    .foregroundStyle(Color.inkFaded)
            }
            if let mb = entry.pressureMb {
                Text("\(String(format: "%.1f", mb)) mb")
                    .font(.cozyBody.weight(.semibold))
                    .foregroundStyle(Color.ink)
            } else {
                Text("—").foregroundStyle(Color.inkFaded)
            }
            if let delta = entry.pressureTrend6hMb {
                Text("\(delta >= 0 ? "+" : "")\(String(format: "%.1f", delta)) / 6h")
                    .font(.cozyCaption)
                    .foregroundStyle(Color.inkFaded)
            } else if let trend = entry.pressureTrend {
                Text(trend.display)
                    .font(.cozyCaption)
                    .foregroundStyle(Color.inkFaded)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var windBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "wind")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.inkFaded)
                Text("WIND")
                    .font(.fieldLabel)
                    .foregroundStyle(Color.inkFaded)
            }
            if let kmh = entry.windSpeedKmh {
                Text("\(Int(kmh.rounded())) km/h")
                    .font(.cozyBody.weight(.semibold))
                    .foregroundStyle(Color.ink)
            } else {
                Text("—").foregroundStyle(Color.inkFaded)
            }
            if let deg = entry.windDirectionDegrees {
                Text(compass(for: deg))
                    .font(.cozyCaption)
                    .foregroundStyle(Color.inkFaded)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var airBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let symbol = entry.conditionSymbol {
                    Image(systemName: symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.sunset)
                }
                Text("AIR")
                    .font(.fieldLabel)
                    .foregroundStyle(Color.inkFaded)
            }
            if let tempC = entry.airTempC {
                let f = tempC * 9 / 5 + 32
                Text("\(Int(f.rounded()))°F")
                    .font(.cozyBody.weight(.semibold))
                    .foregroundStyle(Color.ink)
            } else {
                Text("—").foregroundStyle(Color.inkFaded)
            }
            if let cloud = entry.cloudCoverage {
                Text("\(Int((cloud * 100).rounded()))% cloud")
                    .font(.cozyCaption)
                    .foregroundStyle(Color.inkFaded)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sunMoonRow: some View {
        HStack(spacing: 14) {
            if let sunrise = entry.sunriseAt {
                Label(timeText(sunrise), systemImage: "sunrise.fill")
                    .font(.cozyCaption)
                    .foregroundStyle(Color.inkFaded)
            }
            if let sunset = entry.sunsetAt {
                Label(timeText(sunset), systemImage: "sunset.fill")
                    .font(.cozyCaption)
                    .foregroundStyle(Color.inkFaded)
            }
            if let phase = entry.moonPhase {
                Label("Moon \(Int((phase * 100).rounded()))%", systemImage: "moon.stars.fill")
                    .font(.cozyCaption)
                    .foregroundStyle(Color.inkFaded)
            }
            Spacer()
        }
    }

    private func compass(for degrees: Double) -> String {
        let dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]
        let norm = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let idx = Int(norm / 22.5 + 0.5) % 16
        return dirs[idx]
    }

    private func timeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}
