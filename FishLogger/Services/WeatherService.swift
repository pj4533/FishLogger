import Foundation
import CoreLocation
import WeatherKit
import Observation

enum WeatherServiceError: Error, LocalizedError {
    case historicalHourMissing
    var errorDescription: String? {
        switch self {
        case .historicalHourMissing:
            return "WeatherKit returned no hourly data for the requested time."
        }
    }
}

struct ForecastBundle {
    let current: CurrentWeather
    let daily: Forecast<DayWeather>
    let hourly: Forecast<HourWeather>
}

struct HistoricalHourlySnapshot {
    /// The hour closest to the catch timestamp.
    let atHour: HourWeather
    /// Surrounding 7-hour window (up to ±3h of `atHour`) used for trend derivation.
    let window: [HourWeather]
}

@MainActor
@Observable
final class WeatherService {
    static let shared = WeatherService()

    private let service = WeatherKit.WeatherService.shared

    /// Current conditions plus 10-day daily + 240h hourly forecasts.
    func currentAndForecast(at location: CLLocation) async throws -> ForecastBundle {
        let result = try await service.weather(
            for: location,
            including: .current, .daily, .hourly
        )
        // Tuple unpacks in declaration order.
        return ForecastBundle(current: result.0, daily: result.1, hourly: result.2)
    }

    /// Historical hourly weather centered on `date`. Requests a ±3h window and
    /// returns the closest hour plus the full window for trend calculations.
    func historical(at location: CLLocation, date: Date) async throws -> HistoricalHourlySnapshot {
        let start = date.addingTimeInterval(-3 * 3600)
        let end = date.addingTimeInterval(3 * 3600)

        let hourly = try await service.weather(
            for: location,
            including: .hourly(startDate: start, endDate: end)
        )

        let window = Array(hourly.forecast)
        guard
            let closest = window.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
        else {
            throw WeatherServiceError.historicalHourMissing
        }

        return HistoricalHourlySnapshot(atHour: closest, window: window)
    }
}

extension PressureTrend {
    init(_ wk: WeatherKit.PressureTrend) {
        switch wk {
        case .rising:     self = .rising
        case .falling:    self = .falling
        case .steady:     self = .steady
        @unknown default: self = .steady
        }
    }
}
