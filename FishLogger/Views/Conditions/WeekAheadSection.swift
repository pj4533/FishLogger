import SwiftUI
import WeatherKit

struct WeekAheadSection: View {
    let snapshot: ConditionsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WEEK AHEAD")
                .font(.fieldLabel)
                .foregroundStyle(Color.inkFaded)
                .padding(.leading, 4)

            ForEach(Array(snapshot.bundle.daily.prefix(10)), id: \.date) { day in
                DayConditionCard(day: day, hourly: hours(for: day), snapshot: snapshot)
            }
        }
    }

    private func hours(for day: DayWeather) -> [HourWeather] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day.date)
        let end = start.addingTimeInterval(24 * 3600)
        return snapshot.bundle.hourly.filter { $0.date >= start && $0.date < end }
    }
}

struct DayConditionCard: View {
    let day: DayWeather
    let hourly: [HourWeather]
    let snapshot: ConditionsSnapshot
    @State private var expanded: Bool = false

    private var solunar: Solunar? {
        snapshot.solunarByDay[Calendar.current.startOfDay(for: day.date)]
    }

    var body: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 12) {
                header

                if let bestMajor = solunar?.majors.first {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.stars.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.sunset)
                        Text("Major \(timeRange(bestMajor))")
                            .font(.cozyCaption)
                            .foregroundStyle(Color.inkFaded)
                        Spacer()
                    }
                }

                if expanded {
                    expandedDetail
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack {
                        Text(expanded ? "Hide hourly" : "Show hourly")
                            .font(.cozyCaption.weight(.semibold))
                            .foregroundStyle(Color.sunset)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.sunset)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayNameText)
                    .font(.species)
                    .foregroundStyle(Color.ink)
                Text(dateText)
                    .font(.cozyCaption)
                    .foregroundStyle(Color.inkFaded)
            }
            Spacer()
            Image(systemName: day.symbolName)
                .font(.title2)
                .foregroundStyle(Color.sunset)
            VStack(alignment: .trailing, spacing: 2) {
                Text(tempRange)
                    .font(.species)
                    .foregroundStyle(Color.ink)
                HStack(spacing: 4) {
                    Image(systemName: "cloud.rain.fill")
                        .font(.caption2)
                    Text("\(Int((day.precipitationChance * 100).rounded()))%")
                        .font(.cozyCaption)
                }
                .foregroundStyle(Color.inkFaded)
            }
        }
    }

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().background(Color.bark.opacity(0.4))

            // Sunrise / sunset / moon phase
            HStack(spacing: 14) {
                detailItem(icon: "sunrise.fill", text: timeText(day.sun.sunrise))
                detailItem(icon: "sunset.fill", text: timeText(day.sun.sunset))
                if let phase = solunar?.moonPhase {
                    detailItem(icon: moonSymbol(for: phase), text: moonPhaseText(phase))
                }
                Spacer()
            }

            // Pressure sparkline (hourly)
            if !hourly.isEmpty {
                PressureSparkline(hourly: hourly)
                    .frame(height: 36)
            }

            // Wind range
            HStack(spacing: 10) {
                Image(systemName: "wind")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.inkFaded)
                Text("Wind \(windRange)")
                    .font(.cozyCaption)
                    .foregroundStyle(Color.inkFaded)
                Spacer()
            }
        }
    }

    private var dayNameText: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        let today = Calendar.current.startOfDay(for: .now)
        let dayKey = Calendar.current.startOfDay(for: day.date)
        if dayKey == today { return "Today" }
        if dayKey == today.addingTimeInterval(24 * 3600) { return "Tomorrow" }
        return f.string(from: day.date)
    }

    private var dateText: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: day.date)
    }

    private var tempRange: String {
        let low = Int(day.lowTemperature.converted(to: .fahrenheit).value.rounded())
        let high = Int(day.highTemperature.converted(to: .fahrenheit).value.rounded())
        return "\(low)° / \(high)°"
    }

    private var windRange: String {
        let speeds = hourly.map { $0.wind.speed.converted(to: .kilometersPerHour).value }
        guard let lo = speeds.min(), let hi = speeds.max() else {
            let s = day.wind.speed.converted(to: .kilometersPerHour).value
            return "\(Int(s.rounded())) km/h"
        }
        return "\(Int(lo.rounded()))–\(Int(hi.rounded())) km/h"
    }

    private func timeText(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    private func timeRange(_ interval: DateInterval) -> String {
        "\(timeText(interval.start))–\(timeText(interval.end))"
    }

    private func detailItem(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption.weight(.semibold)).foregroundStyle(Color.inkFaded)
            Text(text).font(.cozyCaption).foregroundStyle(Color.inkFaded)
        }
    }

    private func moonSymbol(for phase: Double) -> String {
        switch phase {
        case 0..<0.03:      return "moonphase.new.moon"
        case 0.03..<0.22:   return "moonphase.waxing.crescent"
        case 0.22..<0.28:   return "moonphase.first.quarter"
        case 0.28..<0.47:   return "moonphase.waxing.gibbous"
        case 0.47..<0.53:   return "moonphase.full.moon"
        case 0.53..<0.72:   return "moonphase.waning.gibbous"
        case 0.72..<0.78:   return "moonphase.last.quarter"
        case 0.78..<0.97:   return "moonphase.waning.crescent"
        default:            return "moonphase.new.moon"
        }
    }

    private func moonPhaseText(_ phase: Double) -> String {
        switch phase {
        case 0..<0.03, 0.97...1.0: return "New"
        case 0.03..<0.22:          return "Waxing cr."
        case 0.22..<0.28:          return "1st qtr"
        case 0.28..<0.47:          return "Waxing gib."
        case 0.47..<0.53:          return "Full"
        case 0.53..<0.72:          return "Waning gib."
        case 0.72..<0.78:          return "Last qtr"
        case 0.78..<0.97:          return "Waning cr."
        default:                   return "—"
        }
    }
}

private struct PressureSparkline: View {
    let hourly: [HourWeather]

    var body: some View {
        GeometryReader { geo in
            let samples = hourly.map { $0.pressure.converted(to: .millibars).value }
            if let lo = samples.min(), let hi = samples.max(), hi > lo {
                let range = hi - lo
                Path { p in
                    for (i, v) in samples.enumerated() {
                        let x = geo.size.width * CGFloat(i) / CGFloat(max(1, samples.count - 1))
                        let y = geo.size.height * (1 - CGFloat((v - lo) / range))
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else       { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(Color.sunset, lineWidth: 1.5)
                .overlay(alignment: .topTrailing) {
                    Text("Pressure \(String(format: "%.1f", lo))–\(String(format: "%.1f", hi)) mb")
                        .font(.cozyCaption)
                        .foregroundStyle(Color.inkFaded)
                }
            } else {
                Text("Pressure flat")
                    .font(.cozyCaption)
                    .foregroundStyle(Color.inkFaded)
            }
        }
    }
}
