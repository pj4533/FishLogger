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
                        Text("BEST TIME TO FISH · NEXT 7 DAYS")
                            .font(.fieldLabel)
                            .foregroundStyle(Color.inkFaded)
                        Text(dateText(best.interval))
                            .font(.species)
                            .foregroundStyle(Color.ink)
                        if !best.rationale.isEmpty {
                            Text(displayRationale(best.rationale))
                                .font(.cozyCaption)
                                .foregroundStyle(Color.inkFaded)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                }
            }
        } else {
            EmptyView()
        }
    }

    /// Join and capitalize the scorer's lowercase reason tags into a readable
    /// fragment, e.g. "Overcast, falling pressure, solunar major."
    private func displayRationale(_ reasons: [String]) -> String {
        guard let first = reasons.first else { return "" }
        let head = first.prefix(1).uppercased() + first.dropFirst()
        let rest = reasons.dropFirst()
        if rest.isEmpty { return head }
        return head + ", " + rest.joined(separator: ", ")
    }

    private func dateText(_ interval: DateInterval) -> String {
        let df = DateFormatter()
        df.dateFormat = "EEE h:mm a"
        let tf = DateFormatter()
        tf.dateFormat = "h:mm a"
        return "\(df.string(from: interval.start))–\(tf.string(from: interval.end))"
    }
}
