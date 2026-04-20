import SwiftUI
import WeatherKit

struct BestWindowBanner: View {
    let snapshot: ConditionsSnapshot

    private var dailyByDate: [Date: DayWeather] {
        let cal = Calendar.current
        return Dictionary(uniqueKeysWithValues: snapshot.bundle.daily.map {
            (cal.startOfDay(for: $0.date), $0)
        })
    }

    /// Scope to the next 7 days to keep the scan focused and the message punchy.
    private var hoursWindow: [HourWeather] {
        let cutoff = Date().addingTimeInterval(7 * 24 * 3600)
        return snapshot.bundle.hourly.filter { $0.date >= .now && $0.date <= cutoff }
    }

    private var best: BestFishingWindow? {
        ConditionsScorer.bestWindow(
            hours: hoursWindow,
            dailyByDate: dailyByDate,
            solunarByDate: snapshot.solunarByDay
        )
    }

    var body: some View {
        if let best {
            CozyCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "star.fill")
                        .font(.title2)
                        .foregroundStyle(Color.sunset)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("BEST WINDOW")
                            .font(.fieldLabel)
                            .foregroundStyle(Color.inkFaded)
                        Text(dateText(best.interval))
                            .font(.species)
                            .foregroundStyle(Color.ink)
                        if !best.rationale.isEmpty {
                            Text(best.rationale.joined(separator: " · "))
                                .font(.cozyCaption)
                                .foregroundStyle(Color.inkFaded)
                        }
                    }
                    Spacer()
                }
            }
        } else {
            EmptyView()
        }
    }

    private func dateText(_ interval: DateInterval) -> String {
        let df = DateFormatter()
        df.dateFormat = "EEE h:mm a"
        let tf = DateFormatter()
        tf.dateFormat = "h:mm a"
        return "\(df.string(from: interval.start))–\(tf.string(from: interval.end))"
    }
}
