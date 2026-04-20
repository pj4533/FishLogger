import SwiftUI
import CoreLocation
import WeatherKit

/// Snapshot of everything we fetched for a FishingArea — passed to child views
/// so they don't each re-fetch.
struct ConditionsSnapshot {
    let area: FishingArea
    let bundle: ForecastBundle
    /// Solunar keyed by the start-of-day in the user's local calendar.
    let solunarByDay: [Date: Solunar]
    let fetchedAt: Date
}

enum ConditionsLoadState {
    case idle
    case loading
    case loaded(ConditionsSnapshot)
    case failed(String)
}

struct ConditionsDetailView: View {
    let area: FishingArea

    @State private var state: ConditionsLoadState = .idle

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch state {
                case .idle, .loading:
                    loadingView
                case .failed(let msg):
                    failedView(msg)
                case .loaded(let snapshot):
                    loadedView(snapshot)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.paper.ignoresSafeArea())
        .task(id: area.id) {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private var loadingView: some View {
        CozyCard {
            HStack {
                ProgressView()
                Text("Reading the sky…")
                    .font(.cozyBody)
                    .foregroundStyle(Color.inkFaded)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func failedView(_ msg: String) -> some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Couldn't load conditions", systemImage: "exclamationmark.triangle.fill")
                    .font(.species)
                    .foregroundStyle(Color.ink)
                Text(msg)
                    .font(.cozyCaption)
                    .foregroundStyle(Color.inkFaded)
                Button {
                    Task { await load() }
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                        .font(.cozyBody.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.sunset))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loadedView(_ snapshot: ConditionsSnapshot) -> some View {
        VStack(spacing: 16) {
            CurrentConditionsCard(snapshot: snapshot)
            TodayStripView(snapshot: snapshot)
            BestWindowBanner(snapshot: snapshot)
            WeekAheadSection(snapshot: snapshot)
        }
    }

    @MainActor
    private func load() async {
        state = .loading
        let center = CLLocation(
            latitude: area.centroid.latitude,
            longitude: area.centroid.longitude
        )
        do {
            let bundle = try await WeatherService.shared.currentAndForecast(at: center)
            let solunar = buildSolunar(bundle: bundle, location: center)
            state = .loaded(ConditionsSnapshot(
                area: area,
                bundle: bundle,
                solunarByDay: solunar,
                fetchedAt: .now
            ))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func buildSolunar(bundle: ForecastBundle, location: CLLocation) -> [Date: Solunar] {
        var byDay: [Date: Solunar] = [:]
        let cal = Calendar.current
        for day in bundle.daily {
            let dayKey = cal.startOfDay(for: day.date)
            byDay[dayKey] = SolunarCalculator.compute(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                date: day.date
            )
        }
        // Ensure "today" is covered even if WeatherKit daily doesn't include it.
        let today = cal.startOfDay(for: .now)
        if byDay[today] == nil {
            byDay[today] = SolunarCalculator.compute(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                date: .now
            )
        }
        return byDay
    }
}
