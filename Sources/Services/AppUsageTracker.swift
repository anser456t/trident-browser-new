import Foundation
import UIKit
import Combine

/// Tracks real, on-device time spent inside Trident itself, bucketed by hour
/// for today. iOS does not let any third-party app read the system-wide
/// Screen Time total for other apps — that data is sandboxed to Apple's own
/// Screen Time / Family Controls stack — so this widget shows genuine
/// in-app activity instead of fabricating a number that looks like it, which
/// would be misleading.
@MainActor
final class AppUsageTracker: ObservableObject {
    static let shared = AppUsageTracker()

    /// Minutes spent in the app this calendar day, indexed by hour (0...23).
    @Published private(set) var hourlyMinutesToday: [Double] = Array(repeating: 0, count: 24)

    private let defaultsKey = "trident.appUsage.v1"
    private var sessionStart: Date?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        loadToday()
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.sessionDidBegin() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.sessionDidEnd() }
            .store(in: &cancellables)
        sessionDidBegin()
    }

    var totalMinutesToday: Double {
        hourlyMinutesToday.reduce(0, +) + currentSessionMinutesSoFar
    }

    var formattedTotalToday: String {
        let total = Int(totalMinutesToday.rounded())
        let hours = total / 60
        let minutes = total % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private var currentSessionMinutesSoFar: Double {
        guard let sessionStart else { return 0 }
        return Date().timeIntervalSince(sessionStart) / 60
    }

    private func sessionDidBegin() {
        rolloverIfNeeded()
        sessionStart = Date()
    }

    private func sessionDidEnd() {
        guard let start = sessionStart else { return }
        recordInterval(from: start, to: Date())
        sessionStart = nil
        saveToday()
    }

    /// Splits an active interval across hour buckets (handles the rare case
    /// of a session spanning a midnight or hour boundary) and adds it in.
    private func recordInterval(from start: Date, to end: Date) {
        guard end > start else { return }
        let calendar = Calendar.current
        var cursor = start
        while cursor < end {
            rolloverIfNeeded(referenceDate: cursor)
            let hour = calendar.component(.hour, from: cursor)
            let hourStart = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: cursor) ?? cursor
            let nextHourBoundary = calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? end
            let segmentEnd = min(end, nextHourBoundary)
            let minutes = segmentEnd.timeIntervalSince(cursor) / 60
            if hour >= 0 && hour < hourlyMinutesToday.count {
                hourlyMinutesToday[hour] += minutes
            }
            cursor = segmentEnd
        }
    }

    private func rolloverIfNeeded(referenceDate: Date = Date()) {
        let todayKey = Self.dayKey(for: referenceDate)
        let storedKey = UserDefaults.standard.string(forKey: defaultsKey + ".day")
        if storedKey != todayKey {
            hourlyMinutesToday = Array(repeating: 0, count: 24)
            UserDefaults.standard.set(todayKey, forKey: defaultsKey + ".day")
            saveToday()
        }
    }

    private func loadToday() {
        let todayKey = Self.dayKey(for: Date())
        let storedKey = UserDefaults.standard.string(forKey: defaultsKey + ".day")
        guard storedKey == todayKey,
              let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([Double].self, from: data),
              decoded.count == 24 else {
            hourlyMinutesToday = Array(repeating: 0, count: 24)
            UserDefaults.standard.set(todayKey, forKey: defaultsKey + ".day")
            return
        }
        hourlyMinutesToday = decoded
    }

    private func saveToday() {
        guard let data = try? JSONEncoder().encode(hourlyMinutesToday) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
