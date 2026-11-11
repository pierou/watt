import Foundation

/// A half-open `[start, end)` window inside a day, expressed in minutes from local midnight.
/// An `endMinute` that is not after `startMinute` wraps past midnight (e.g. 22:00-06:00).
struct TariffWindow: Equatable, Hashable {
    let startMinute: Int
    let endMinute: Int

    init?(text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "-", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 2, let start = TariffWindow.minute(of: parts[0]), let end = TariffWindow.minute(of: parts[1]) else {
            return nil
        }
        startMinute = start
        endMinute = end
    }

    init(startMinute: Int, endMinute: Int) {
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    /// "22:00-06:00"
    var text: String { "\(TariffWindow.clock(startMinute))-\(TariffWindow.clock(endMinute))" }

    var wrapsMidnight: Bool { endMinute <= startMinute }

    func contains(_ minute: Int) -> Bool {
        wrapsMidnight ? (minute >= startMinute || minute < endMinute)
                      : (minute >= startMinute && minute < endMinute)
    }

    /// Minutes from local midnight at which this window starts or stops.
    var boundaries: [Int] { [startMinute, endMinute] }

    private static func minute(of clock: String) -> Int? {
        let parts = clock.split(separator: ":", maxSplits: 1).map { Int($0) }
        guard parts.count == 2, let h = parts[0], let m = parts[1], (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    private static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

/// Electricity pricing: a single flat rate, or separate peak / off-peak rates with
/// off-peak windows. Windows are compared against the machine's local time zone, so a
/// laptop that travels charges the tariff of wherever it currently is.
struct Tariff: Equatable {
    enum Mode: String, Codable {
        case flat
        case peakOffPeak
    }

    var mode: Mode = .flat
    /// Price per kWh while the clock is outside every off-peak window — and the only
    /// price there is in `.flat` mode.
    var peakRate: Double = 0.12
    /// Price per kWh inside an off-peak window.
    var offPeakRate: Double = 0.09
    var offPeakWindows: [TariffWindow] = [TariffWindow(startMinute: 22 * 60, endMinute: 6 * 60)]

    var isTimeOfUse: Bool { mode == .peakOffPeak }

    // MARK: Rates

    func rate(at date: Date = Date(), calendar: Calendar = .current) -> Double {
        isTimeOfUse && isOffPeak(at: date, calendar: calendar) ? offPeakRate : peakRate
    }

    func isOffPeak(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard isTimeOfUse else { return false }
        return contains(minuteOfDay(date, calendar: calendar))
    }

    func contains(_ minute: Int) -> Bool {
        offPeakWindows.contains { $0.contains(minute) }
    }

    // MARK: Transitions

    /// When the current rate stops applying, i.e. the next window boundary.
    func nextTransition(from date: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard isTimeOfUse, !offPeakWindows.isEmpty else { return nil }

        let now = minuteOfDay(date)
        let bandNow = contains(now)
        let boundaries = Array(Set(offPeakWindows.flatMap { $0.boundaries })).sorted()

        // Look at each boundary today, then tomorrow, for the first one that flips the band.
        for candidate in boundaries + boundaries.map({ $0 + 1440 }) {
            if candidate > now && contains(candidate % 1440) != bandNow {
                return calendar.date(byAdding: .minute, value: candidate - now, to: truncateToMinute(date, calendar: calendar))
            }
        }
        return nil
    }

    /// "Off-peak · 0.090/kWh · until 06:00", without the leading band word.
    var nextTransitionText: String? {
        guard let next = nextTransition() else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return "until \(f.string(from: next))"
    }

    // MARK: Text

    /// Parses a user-entered schedule, e.g. "22:00-06:00, 14:00-16:00".
    /// Returns nil when any entry is unreadable, so a typo never silently changes a bill.
    static func parseWindows(_ text: String) -> [TariffWindow]? {
        let entries = text.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
                          .map { $0.trimmingCharacters(in: .whitespaces) }
                          .filter { !$0.isEmpty }
        guard !entries.isEmpty else { return nil }
        var windows: [TariffWindow] = []
        for entry in entries {
            guard let window = TariffWindow(text: entry) else { return nil }
            windows.append(window)
        }
        return windows
    }

    static func windowsText(_ windows: [TariffWindow]) -> String {
        windows.map(\.text).joined(separator: ", ")
    }

    // MARK: Minutes

    private func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func truncateToMinute(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySetting: .second, value: 0, of: date) ?? date
    }
}

/// Display currency for money figures. The minor unit is what the narrow stat columns show.
enum Currency: String, CaseIterable, Codable {
    case usd, eur, gbp, cad, sek

    var symbol: String {
        switch self {
        case .usd: return "$"
        case .eur: return "€"
        case .gbp: return "£"
        case .cad: return "C$"
        case .sek: return "kr"
        }
    }

    var minorSymbol: String {
        switch self {
        case .usd, .cad: return "¢"
        case .eur: return "c"
        case .gbp: return "p"
        case .sek: return "ö"
        }
    }
}
