import SwiftUI
import UIKit

/// The "Good afternoon" header shown at the top of the Start page. Split out
/// from the widget row below so the two can be reordered independently.
struct HomeGreetingHeader: View {
    @EnvironmentObject var settings: AppSettings
    @State private var isEditingName = false
    @State private var nameDraft = ""

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting + ",")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                Text(settings.userDisplayName + ".")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(settings.accentColor)
            }
            Spacer()
            Button {
                nameDraft = settings.userDisplayName == "there" ? "" : settings.userDisplayName
                isEditingName = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(9)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .alert("Your Name", isPresented: $isEditingName) {
            TextField("Name", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                settings.userDisplayName = trimmed.isEmpty ? "there" : trimmed
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        return hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
    }
}

/// The three-card widget row shown on the Start page: live weather, in-app
/// Screen Time, and a clock. (Previously bundled with the greeting header in
/// a single `HomeWidgetsView` — split apart so `StartPageView` can place the
/// greeting, search bar, Quick Access, and this row in any order.)
struct HomeWidgetsRow: View {
    @StateObject private var weather = WeatherService()
    @StateObject private var usage = AppUsageTracker.shared

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                WeatherWidgetCard(weather: weather)
                ScreenTimeWidgetCard(usage: usage)
                ClockWidgetCard()
            }
            VStack(spacing: 12) {
                WeatherWidgetCard(weather: weather)
                HStack(spacing: 12) {
                    ScreenTimeWidgetCard(usage: usage)
                    ClockWidgetCard()
                }
            }
        }
        .onAppear { weather.refresh() }
    }
}

// MARK: - Weather

private struct WeatherWidgetCard: View {
    @ObservedObject var weather: WeatherService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch weather.state {
            case .loading:
                HStack {
                    ProgressView().tint(.white)
                    Spacer()
                }
                Spacer(minLength: 40)

            case .unavailable(let reason):
                HStack(spacing: 6) {
                    Image(systemName: reason == .locationUnavailable ? "location.slash" : "cloud.slash")
                        .foregroundStyle(.white.opacity(0.45))
                    Text("Weather unavailable")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Text(reason == .locationUnavailable
                     ? "Enable location access to see local conditions."
                     : "Couldn't load weather right now.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.35))
                if reason == .locationUnavailable {
                    Button {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "location")
                            Text("Enable location")
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Tap to retry")
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: 20)

            case .loaded(let snapshot):
                HStack(alignment: .top) {
                    HStack(spacing: 8) {
                        Image(systemName: snapshot.symbolName)
                            .font(.system(size: 26))
                            .symbolRenderingMode(.multicolor)
                        Text("\(Int(snapshot.temperature.rounded()))°")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.conditionDescription)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                    if let locationName = snapshot.locationName {
                        Text(locationName)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Text("H:\(Int(snapshot.highTemperature.rounded()))°  L:\(Int(snapshot.lowTemperature.rounded()))°")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }

                if !snapshot.hourly.isEmpty {
                    Divider().overlay(Color.white.opacity(0.08))
                    HStack {
                        ForEach(snapshot.hourly) { hour in
                            VStack(spacing: 4) {
                                Text(hour.hourLabel)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.5))
                                Image(systemName: hour.symbolName)
                                    .font(.system(size: 11))
                                    .symbolRenderingMode(.multicolor)
                                Text("\(Int(hour.temperature.rounded()))°")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(GlassPanel(cornerRadius: 18) { Color.clear })
        .contentShape(Rectangle())
        .onTapGesture {
            if case .unavailable(.fetchFailed) = weather.state {
                weather.refresh()
            }
        }
    }
}

// MARK: - Screen Time (in-app usage)

private struct ScreenTimeWidgetCard: View {
    @ObservedObject var usage: AppUsageTracker
    @State private var showingDetail = false

    private var activeHours: [Int] {
        let currentHour = Calendar.current.component(.hour, from: .now)
        return Array(0...max(currentHour, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Screen Time")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
            Text(usage.formattedTotalToday)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
            Text("Today in Trident")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))

            hourlyBars
                .frame(height: 40)

            Button { showingDetail = true } label: {
                HStack {
                    Text("View Activity").font(.caption2.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(GlassPanel(cornerRadius: 18) { Color.clear })
        .sheet(isPresented: $showingDetail) {
            ScreenTimeDetailView(usage: usage)
        }
    }

    private var hourlyBars: some View {
        let values = activeHours.map { usage.hourlyMinutesToday[$0] }
        let maxValue = max(values.max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(activeHours, id: \.self) { hour in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.28))
                    .frame(height: max(3, CGFloat(usage.hourlyMinutesToday[hour] / maxValue) * 40))
            }
        }
    }
}

private struct ScreenTimeDetailView: View {
    @ObservedObject var usage: AppUsageTracker
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(usage.formattedTotalToday)
                            .font(.system(size: 32, weight: .semibold))
                        Text("Time spent in Trident today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(0..<24, id: \.self) { hour in
                            VStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.accentColor.opacity(0.55))
                                    .frame(height: max(2, CGFloat(usage.hourlyMinutesToday[hour]) * 2))
                                if hour % 6 == 0 {
                                    Text(hourLabel(hour))
                                        .font(.system(size: 8))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 120, alignment: .bottom)

                    Text("Trident can only measure the time you spend inside this app — iOS doesn't let third-party apps read your system-wide Screen Time.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? .now
        return formatter.string(from: date).lowercased()
    }
}

// MARK: - Clock

private struct ClockWidgetCard: View {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("hmm")
        return formatter
    }()
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        return formatter
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let calendar = Calendar.current

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer()
                    Text(Self.dayFormatter.string(from: now))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Text(Self.timeFormatter.string(from: now))
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer(minLength: 4)

                ClockFaceView(date: now, calendar: calendar)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxHeight: 70)

                Spacer(minLength: 4)

                Text(TimeZone.current.localizedName(for: .standard, locale: .current) ?? TimeZone.current.identifier)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(GlassPanel(cornerRadius: 18) { Color.clear })
    }
}

private struct ClockFaceView: View {
    let date: Date
    let calendar: Calendar

    var body: some View {
        let hour = Double(calendar.component(.hour, from: date) % 12)
        let minute = Double(calendar.component(.minute, from: date))
        let second = Double(calendar.component(.second, from: date))
        let hourAngle = Angle.degrees((hour + minute / 60) / 12 * 360)
        let minuteAngle = Angle.degrees((minute + second / 60) / 60 * 360)

        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2

            // Angles are pinned to CGFloat everywhere below. Leaving them as
            // plain (inferred) Double, mixed into CGFloat-heavy arithmetic
            // with `center`/`radius`, is what made the compiler unable to
            // decide between the CGFloat and Double overloads of `cos`/`sin`
            // ("ambiguous use of 'cos'") — an explicit type on each angle
            // value resolves the overload before it's ever called.
            for tick in 0..<12 {
                let angle: CGFloat = CGFloat(Angle.degrees(Double(tick) / 12 * 360).radians) - .pi / 2
                let inner = CGPoint(x: center.x + cos(angle) * radius * 0.86, y: center.y + sin(angle) * radius * 0.86)
                let outer = CGPoint(x: center.x + cos(angle) * radius * 0.98, y: center.y + sin(angle) * radius * 0.98)
                var path = Path()
                path.move(to: inner)
                path.addLine(to: outer)
                context.stroke(path, with: .color(.white.opacity(0.18)), lineWidth: 1.2)
            }

            var rim = Path()
            rim.addEllipse(in: CGRect(x: center.x - radius * 0.98, y: center.y - radius * 0.98, width: radius * 1.96, height: radius * 1.96))
            context.stroke(rim, with: .color(.white.opacity(0.12)), lineWidth: 1)

            func hand(angle: Angle, length: CGFloat, width: CGFloat, opacity: Double) {
                let radians: CGFloat = CGFloat(angle.radians) - .pi / 2
                let end = CGPoint(x: center.x + cos(radians) * radius * length, y: center.y + sin(radians) * radius * length)
                var path = Path()
                path.move(to: center)
                path.addLine(to: end)
                context.stroke(path, with: .color(.white.opacity(opacity)), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }

            hand(angle: hourAngle, length: 0.5, width: 2.6, opacity: 0.9)
            hand(angle: minuteAngle, length: 0.78, width: 1.8, opacity: 0.85)

            context.fill(Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)), with: .color(.white.opacity(0.9)))
        }
    }
}
