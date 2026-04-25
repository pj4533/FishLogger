import SwiftUI

/// Renders the conditions/weather captured for a fishing session. Drop-in
/// replacement for the previous per-catch conditions section — now a session
/// can show conditions even if no fish were caught.
struct ConditionsSessionCard: View {
    let session: Session

    var body: some View {
        if session.conditionsFetchedAt != nil {
            CozyCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("CONDITIONS")
                        .font(.fieldLabel)
                        .foregroundStyle(Color.inkFaded)

                    HStack(alignment: .top, spacing: 16) {
                        pressureBlock
                        windBlock
                        airBlock
                    }

                    if session.sunriseAt != nil || session.sunsetAt != nil || session.moonPhase != nil {
                        Divider().background(Color.bark.opacity(0.4))
                        sunMoonRow
                    }

                    if !session.solunarMajors.isEmpty || !session.solunarMinors.isEmpty {
                        Divider().background(Color.bark.opacity(0.4))
                        solunarRow
                    }
                }
            }
        }
    }

    private var pressureBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let trend = session.pressureTrend {
                    Image(systemName: trend.symbolName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(trend == .falling ? Color.sunset : Color.inkFaded)
                }
                Text("PRESSURE")
                    .font(.fieldLabel)
                    .foregroundStyle(Color.inkFaded)
            }
            if let mb = session.pressureMb {
                Text("\(String(format: "%.1f", mb)) mb")
                    .font(.cozyBody.weight(.semibold))
                    .foregroundStyle(Color.ink)
            } else {
                Text("—").foregroundStyle(Color.inkFaded)
            }
            if let delta = session.pressureTrend6hMb {
                Text("\(delta >= 0 ? "+" : "")\(String(format: "%.1f", delta)) / 6h")
                    .font(.cozyCaption)
                    .foregroundStyle(Color.inkFaded)
            } else if let trend = session.pressureTrend {
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
            if let kmh = session.windSpeedKmh {
                Text("\(Int(kmh.rounded())) km/h")
                    .font(.cozyBody.weight(.semibold))
                    .foregroundStyle(Color.ink)
            } else {
                Text("—").foregroundStyle(Color.inkFaded)
            }
            if let deg = session.windDirectionDegrees {
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
                if let symbol = session.conditionSymbol {
                    Image(systemName: symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.sunset)
                }
                Text("AIR")
                    .font(.fieldLabel)
                    .foregroundStyle(Color.inkFaded)
            }
            if let tempC = session.airTempC {
                let f = tempC * 9 / 5 + 32
                Text("\(Int(f.rounded()))°F")
                    .font(.cozyBody.weight(.semibold))
                    .foregroundStyle(Color.ink)
            } else {
                Text("—").foregroundStyle(Color.inkFaded)
            }
            if let cloud = session.cloudCoverage {
                Text("\(Int((cloud * 100).rounded()))% cloud")
                    .font(.cozyCaption)
                    .foregroundStyle(Color.inkFaded)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sunMoonRow: some View {
        HStack(spacing: 14) {
            if let sunrise = session.sunriseAt {
                Label(timeText(sunrise), systemImage: "sunrise.fill")
                    .font(.cozyCaption)
                    .foregroundStyle(Color.inkFaded)
            }
            if let sunset = session.sunsetAt {
                Label(timeText(sunset), systemImage: "sunset.fill")
                    .font(.cozyCaption)
                    .foregroundStyle(Color.inkFaded)
            }
            if let phase = session.moonPhase {
                Label("Moon \(Int((phase * 100).rounded()))%", systemImage: "moon.stars.fill")
                    .font(.cozyCaption)
                    .foregroundStyle(Color.inkFaded)
            }
            Spacer()
        }
    }

    private var solunarRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !session.solunarMajors.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.sunset)
                    Text("Majors: \(session.solunarMajors.map { intervalText($0) }.joined(separator: ", "))")
                        .font(.cozyCaption)
                        .foregroundStyle(Color.ink)
                }
            }
            if !session.solunarMinors.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "star")
                        .font(.caption)
                        .foregroundStyle(Color.inkFaded)
                    Text("Minors: \(session.solunarMinors.map { intervalText($0) }.joined(separator: ", "))")
                        .font(.cozyCaption)
                        .foregroundStyle(Color.inkFaded)
                }
            }
        }
    }

    private func intervalText(_ interval: DateInterval) -> String {
        "\(timeText(interval.start))–\(timeText(interval.end))"
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
