import Foundation

/// Approximate solar events from NOAA's fractional-year equations:
/// https://gml.noaa.gov/grad/solcalc/solareqns.PDF
/// Coordinates come from Location Services; dates follow the system time zone.
public struct SolarLocation: Equatable {
    public let latitude: Double
    public let longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude; self.longitude = longitude
    }
    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

public enum SunsetSchedule {
    public static var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = .autoupdatingCurrent
        return result
    }
    public struct Window: Equatable {
        public let start: Date
        public let end: Date
    }
    public static func window(on date: Date, location: SolarLocation, timeZone: TimeZone = .autoupdatingCurrent) -> Window? {
        guard location.isValid else { return nil }
        var localCalendar = calendar
        localCalendar.timeZone = timeZone
        let local = localCalendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = utc.date(from: local)!
        let day = utc.ordinality(of: .day, in: .year, for: midnight)!
        let days = utc.range(of: .day, in: .year, for: midnight)!.count
        let latitude = location.latitude * Double.pi / 180
        let longitude = location.longitude
        func event(zenith: Double) -> Date? {
            var minutes = 1080.0
            // Refine the fractional year at the event's estimated UTC hour.
            for _ in 0..<3 {
                let gamma = 2 * Double.pi / Double(days) * (Double(day - 1) + (minutes / 60 - 12) / 24)
                let equation = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
                    - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
                let declination = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
                    - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma)
                    - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
                let cosine = cos(zenith * Double.pi / 180) / (cos(latitude) * cos(declination))
                    - tan(latitude) * tan(declination)
                // No crossing during polar day/night or uninterrupted twilight.
                guard cosine.isFinite, (-1...1).contains(cosine) else { return nil }
                let angle = acos(cosine) * 180 / Double.pi
                minutes = 720 - 4 * longitude + 4 * angle - equation
            }
            return midnight.addingTimeInterval(minutes * 60)
        }
        guard let start = event(zenith: 90.833), let end = event(zenith: 96), end > start else { return nil }
        return Window(start: start, end: end)
    }
    public static func target(now: Date, configuration: Configuration, state: DisplayState, location: SolarLocation) -> Profile? {
        guard configuration.sunsetAutomation == true, state.isOn else { return nil }
        guard let window = window(on: now, location: location) else { return nil }
        guard now >= window.start else { return nil }
        if let manual = state.lastManualChange, manual >= window.start { return nil }
        let fraction = min(1, max(0, now.timeIntervalSince(window.start) / window.end.timeIntervalSince(window.start)))
        func blend(_ day: Int, _ evening: Int) -> Int {
            Int((Double(day) + Double(evening - day) * fraction).rounded())
        }
        return Profile(temperature: blend(configuration.day.temperature, configuration.evening.temperature),
                       brightness: blend(configuration.day.brightness, configuration.evening.brightness))
    }
    public static func summary(enabled: Bool, now: Date, location: SolarLocation? = nil) -> String {
        guard enabled else { return "Sunset schedule: disabled." }
        guard let location else { return "Sunset schedule: enabled; waiting for system location. See nanoleaf status." }
        guard let window = window(on: now, location: location) else { return "Sunset schedule: no sunset-to-civil-dusk window at the current location today." }
        let formatter = DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "HH:mm z"
        return "Sunset schedule: system location, today \(formatter.string(from: window.start))–\(formatter.string(from: window.end)). No morning switch."
    }
}
