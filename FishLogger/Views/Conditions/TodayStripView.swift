import SwiftUI

/// Horizontal 24h timeline for "today" showing daylight, solunar majors/minors,
/// and a "now" marker. The most at-a-glance fishing summary on the screen.
struct TodayStripView: View {
    let snapshot: ConditionsSnapshot

    private var today: Date { Calendar.current.startOfDay(for: .now) }
    private var solunar: Solunar? { snapshot.solunarByDay[today] }
    private var dayStart: Date { today }
    private var dayEnd: Date { today.addingTimeInterval(24 * 3600) }

    var body: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("TODAY")
                        .font(.fieldLabel)
                        .foregroundStyle(Color.inkFaded)
                    Spacer()
                    if let sunrise = solunar?.sunrise, let sunset = solunar?.sunset {
                        Label("\(timeText(sunrise)) – \(timeText(sunset))", systemImage: "sun.max.fill")
                            .font(.cozyCaption)
                            .foregroundStyle(Color.inkFaded)
                    }
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Base bar
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.waterLight.opacity(0.4))

                        // Daylight band
                        if let sunrise = solunar?.sunrise, let sunset = solunar?.sunset {
                            let x1 = xPos(for: sunrise, width: geo.size.width)
                            let x2 = xPos(for: sunset, width: geo.size.width)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.sunset.opacity(0.35), Color.sunset.opacity(0.15), Color.sunset.opacity(0.35)],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, x2 - x1))
                                .offset(x: x1)
                        }

                        // Major windows
                        ForEach(Array((solunar?.majors ?? []).enumerated()), id: \.offset) { _, window in
                            windowBar(window: window, width: geo.size.width, height: 28, color: Color.sunset.opacity(0.9))
                        }

                        // Minor windows
                        ForEach(Array((solunar?.minors ?? []).enumerated()), id: \.offset) { _, window in
                            windowBar(window: window, width: geo.size.width, height: 16, color: Color.moss.opacity(0.85))
                        }

                        // "Now" marker
                        Rectangle()
                            .fill(Color.ink)
                            .frame(width: 2, height: 40)
                            .offset(x: xPos(for: .now, width: geo.size.width))
                    }
                }
                .frame(height: 44)

                // Hour labels 0, 6, 12, 18, 24
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                            Text(hour == 24 ? "" : "\(hour)")
                                .font(.cozyCaption)
                                .foregroundStyle(Color.inkFaded)
                                .offset(x: geo.size.width * CGFloat(hour) / 24 - 6)
                        }
                    }
                }
                .frame(height: 14)

                legend
            }
        }
    }

    private func windowBar(window: DateInterval, width: CGFloat, height: CGFloat, color: Color) -> some View {
        let x1 = xPos(for: window.start, width: width)
        let x2 = xPos(for: window.end, width: width)
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color)
            .frame(width: max(3, x2 - x1), height: height)
            .offset(x: x1, y: 0)
    }

    private func xPos(for date: Date, width: CGFloat) -> CGFloat {
        let clamped = min(max(date, dayStart), dayEnd)
        let frac = clamped.timeIntervalSince(dayStart) / (24 * 3600)
        return CGFloat(frac) * width
    }

    private func timeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: Color.sunset.opacity(0.9), label: "Major")
            legendItem(color: Color.moss.opacity(0.85), label: "Minor")
            legendItem(color: Color.ink, label: "Now")
            Spacer()
        }
        .font(.cozyCaption)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).foregroundStyle(Color.inkFaded)
        }
    }
}
