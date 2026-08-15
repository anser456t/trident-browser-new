import Foundation
import CoreLocation
import Combine

/// Fetches live current-conditions + hourly forecast for the user's location
/// and publishes a small, view-ready snapshot.
///
/// Uses Open-Meteo (https://open-meteo.com) instead of WeatherKit: it's a
/// free API that needs no API key, no Apple Developer account capability,
/// and no entitlement — once the person grants location access, this just
/// works. All we send it is a latitude/longitude; nothing identifying.
@MainActor
final class WeatherService: NSObject, ObservableObject {
    enum State {
        case loading
        case unavailable(Reason)
        case loaded(Snapshot)
    }

    /// Distinguishes *why* the widget has nothing to show, so the UI isn't
    /// stuck telling someone to "enable location access" after they already
    /// have — that mismatch is what made the widget look permanently broken.
    enum Reason: Equatable {
        /// Location was never granted, or was denied/restricted.
        case locationUnavailable
        /// Location resolved fine; the weather fetch itself failed (network).
        case fetchFailed
    }

    struct HourPoint: Identifiable {
        let id = UUID()
        let hourLabel: String
        let temperature: Double
        let symbolName: String
    }

    struct Snapshot {
        let temperature: Double
        let feelsLike: Double
        let highTemperature: Double
        let lowTemperature: Double
        let conditionDescription: String
        let symbolName: String
        let hourly: [HourPoint]
        let locationName: String?
    }

    @Published private(set) var state: State = .loading

    private let locationManager = CLLocationManager()
    private var didRequestLocation = false
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private let session = URLSession(configuration: .ephemeral)

    override init() {
        super.init()
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.delegate = self
    }

    func refresh() {
        guard !didRequestLocation else { return }
        didRequestLocation = true

        Task {
            do {
                let location = try await requestLocation()
                do {
                    async let snapshot = fetchSnapshot(for: location)
                    async let locationName = reverseGeocode(location)
                    state = .loaded(try await snapshot.withLocationName(await locationName))
                } catch {
                    // Location itself worked — whatever failed after that
                    // (network, or a malformed response) isn't a location
                    // problem, so don't tell the user to "enable location
                    // access" for it.
                    state = .unavailable(.fetchFailed)
                }
            } catch {
                state = .unavailable(.locationUnavailable)
            }
            didRequestLocation = false
        }
    }

    private func reverseGeocode(_ location: CLLocation) async -> String? {
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        let city = placemark.locality ?? placemark.administrativeArea
        guard let city else { return placemark.isoCountryCode }
        if let country = placemark.isoCountryCode {
            return "\(city), \(country)"
        }
        return city
    }

    // MARK: - Open-Meteo

    private var usesFahrenheit: Bool {
        if #available(iOS 16.0, *) {
            return Locale.current.measurementSystem == .us
        }
        return Locale.current.usesMetricSystem == false
    }

    private func fetchSnapshot(for location: CLLocation) async throws -> Snapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(location.coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "temperature_unit", value: usesFahrenheit ? "fahrenheit" : "celsius"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1")
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        return makeSnapshot(from: payload)
    }

    private func makeSnapshot(from payload: OpenMeteoResponse) -> Snapshot {
        let condition = WeatherCondition.forCode(payload.current.weatherCode)

        let formatter = DateFormatter()
        formatter.dateFormat = "ha"

        let nowHour = Date()
        let hourly: [HourPoint] = zip(payload.hourly.time, zip(payload.hourly.temperature2m, payload.hourly.weatherCode))
            .compactMap { timeString, values in
                guard let date = OpenMeteoResponse.isoFormatter.date(from: timeString), date >= nowHour else { return nil }
                let (temp, code) = values
                return HourPoint(
                    hourLabel: formatter.string(from: date).lowercased(),
                    temperature: temp,
                    symbolName: WeatherCondition.forCode(code).symbolName
                )
            }
            .prefix(5)
            .map { $0 }

        return Snapshot(
            temperature: payload.current.temperature2m,
            feelsLike: payload.current.apparentTemperature,
            highTemperature: payload.daily.temperature2mMax.first ?? payload.current.temperature2m,
            lowTemperature: payload.daily.temperature2mMin.first ?? payload.current.temperature2m,
            conditionDescription: condition.description,
            symbolName: condition.symbolName,
            hourly: hourly,
            locationName: nil
        )
    }

    private func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let status = locationManager.authorizationStatus
            switch status {
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                locationManager.requestLocation()
            default:
                continuation.resume(throwing: CLError(.denied))
                self.continuation = nil
            }
        }
    }
}

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            if let continuation {
                // We're mid-`requestLocation()` — resolve (or fail) the
                // in-flight call, same as before.
                if status == .authorizedWhenInUse || status == .authorizedAlways {
                    manager.requestLocation()
                } else if status == .denied || status == .restricted {
                    continuation.resume(throwing: CLError(.denied))
                    self.continuation = nil
                }
            } else if status == .authorizedWhenInUse || status == .authorizedAlways {
                // No request was pending — this fires when the user grants
                // permission from the Settings app (rather than our in-app
                // prompt) after we'd already given up and shown "Weather
                // unavailable". Without this branch the widget just stays
                // stuck on that state forever, since nothing else ever
                // triggers another fetch. Kick a fresh one off now that
                // we're actually authorized.
                didRequestLocation = false
                refresh()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            continuation?.resume(returning: location)
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

// MARK: - Open-Meteo response shape

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature2m: Double
        let apparentTemperature: Double
        let weatherCode: Int

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case weatherCode = "weather_code"
        }
    }

    struct Hourly: Decodable {
        let time: [String]
        let temperature2m: [Double]
        let weatherCode: [Int]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
        }
    }

    struct Daily: Decodable {
        let temperature2mMax: [Double]
        let temperature2mMin: [Double]

        enum CodingKeys: String, CodingKey {
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
        }
    }

    let current: Current
    let hourly: Hourly
    let daily: Daily

    static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

/// Maps Open-Meteo's WMO weather codes to a human description and an SF
/// Symbol, so the UI code doesn't need to know about the underlying API.
private struct WeatherCondition {
    let description: String
    let symbolName: String

    static func forCode(_ code: Int) -> WeatherCondition {
        switch code {
        case 0: return .init(description: "Clear", symbolName: "sun.max.fill")
        case 1: return .init(description: "Mostly Clear", symbolName: "sun.max.fill")
        case 2: return .init(description: "Partly Cloudy", symbolName: "cloud.sun.fill")
        case 3: return .init(description: "Cloudy", symbolName: "cloud.fill")
        case 45, 48: return .init(description: "Foggy", symbolName: "cloud.fog.fill")
        case 51, 53, 55: return .init(description: "Drizzle", symbolName: "cloud.drizzle.fill")
        case 56, 57: return .init(description: "Freezing Drizzle", symbolName: "cloud.sleet.fill")
        case 61, 63, 65: return .init(description: "Rain", symbolName: "cloud.rain.fill")
        case 66, 67: return .init(description: "Freezing Rain", symbolName: "cloud.sleet.fill")
        case 71, 73, 75: return .init(description: "Snow", symbolName: "cloud.snow.fill")
        case 77: return .init(description: "Snow Grains", symbolName: "cloud.snow.fill")
        case 80, 81, 82: return .init(description: "Rain Showers", symbolName: "cloud.heavyrain.fill")
        case 85, 86: return .init(description: "Snow Showers", symbolName: "cloud.snow.fill")
        case 95: return .init(description: "Thunderstorms", symbolName: "cloud.bolt.rain.fill")
        case 96, 99: return .init(description: "Thunderstorms w/ Hail", symbolName: "cloud.bolt.rain.fill")
        default: return .init(description: "Weather", symbolName: "cloud.fill")
        }
    }
}

private extension WeatherService.Snapshot {
    func withLocationName(_ name: String?) -> WeatherService.Snapshot {
        WeatherService.Snapshot(
            temperature: temperature,
            feelsLike: feelsLike,
            highTemperature: highTemperature,
            lowTemperature: lowTemperature,
            conditionDescription: conditionDescription,
            symbolName: symbolName,
            hourly: hourly,
            locationName: name
        )
    }
}
