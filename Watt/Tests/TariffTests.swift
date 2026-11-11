import XCTest
@testable import Watt

/// Tests for the time-of-use pricing model. Everything here is deterministic: dates are
/// built in an explicit calendar and passed in, so no test depends on when it runs or what
/// time zone the machine happens to be in.
final class TariffTests: XCTestCase {

    /// Europe/Paris, so the DST cases below are the transitions France actually has.
    private var paris: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int, month: Int = 11, calendar: Calendar? = nil) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = month; c.day = day; c.hour = hour; c.minute = minute
        return (calendar ?? paris).date(from: c)!
    }

    /// A French-style "heures creuses" schedule: two windows, neither of which starts at midnight.
    private func twoBand() -> Tariff {
        var t = Tariff()
        t.mode = .peakOffPeak
        t.peakRate = 0.20
        t.offPeakRate = 0.15
        t.offPeakWindows = Tariff.parseWindows("00:50-06:50, 14:50-16:50")!
        return t
    }

    // MARK: Band edges

    /// Windows are half-open `[start, end)`: the end minute is already the next band.
    func testEdgesOfEachWindow() {
        let t = twoBand()
        let offPeak: [(Int, Int)] = [(0, 50), (3, 30), (6, 49), (14, 50), (16, 49)]
        let peak: [(Int, Int)] = [(0, 49), (0, 0), (6, 50), (12, 0), (14, 49), (16, 50), (23, 0)]

        for (h, m) in offPeak {
            XCTAssertTrue(t.isOffPeak(at: date(10, h, m)), "expected off-peak at \(h):\(m)")
        }
        for (h, m) in peak {
            XCTAssertFalse(t.isOffPeak(at: date(10, h, m)), "expected peak at \(h):\(m)")
        }
    }

    func testRateFollowsTheBand() {
        let t = twoBand()
        XCTAssertEqual(t.rate(at: date(10, 3, 0)), 0.15, accuracy: 0.0001)
        XCTAssertEqual(t.rate(at: date(10, 12, 0)), 0.20, accuracy: 0.0001)
    }

    /// A flat tariff ignores the schedule completely — switching mode must not leave a
    /// half-applied time-of-use total behind.
    func testFlatModeIgnoresWindows() {
        var t = twoBand()
        t.mode = .flat
        XCTAssertFalse(t.isOffPeak(at: date(10, 3, 0)))
        XCTAssertEqual(t.rate(at: date(10, 3, 0)), 0.20, accuracy: 0.0001)
    }

    // MARK: Windows that wrap midnight

    func testWindowCrossingMidnight() {
        var t = Tariff()
        t.mode = .peakOffPeak
        t.offPeakWindows = Tariff.parseWindows("22:00-06:00")!
        XCTAssertTrue(t.isOffPeak(at: date(10, 22, 0)))
        XCTAssertTrue(t.isOffPeak(at: date(10, 23, 59)))
        XCTAssertTrue(t.isOffPeak(at: date(11, 0, 0)))
        XCTAssertTrue(t.isOffPeak(at: date(11, 5, 59)))
        XCTAssertFalse(t.isOffPeak(at: date(11, 6, 0)))
        XCTAssertFalse(t.isOffPeak(at: date(10, 21, 59)))
    }

    func testAllDayWindow() {
        var t = Tariff()
        t.mode = .peakOffPeak
        t.offPeakWindows = Tariff.parseWindows("00:00-00:00")!
        XCTAssertTrue(t.isOffPeak(at: date(10, 13, 0)))
        XCTAssertNil(t.nextTransition(from: date(10, 13, 0)))
    }

    // MARK: Transitions

    func testNextTransitionLandsOnTheRightBoundary() {
        let t = twoBand()
        XCTAssertEqual(clock(t.nextTransition(from: date(10, 10, 0))), "10-14:50")
        XCTAssertEqual(clock(t.nextTransition(from: date(10, 15, 0))), "10-16:50")
        XCTAssertEqual(clock(t.nextTransition(from: date(10, 3, 0))), "10-06:50")
        // Late evening has to roll over into the next day's window.
        XCTAssertEqual(clock(t.nextTransition(from: date(10, 23, 0))), "11-00:50")
    }

    /// No schedule means no transitions to advertise, rather than a bogus "until 00:00".
    func testNoWindowsMeansNoTransition() {
        var t = Tariff()
        t.mode = .peakOffPeak
        t.offPeakWindows = []
        XCTAssertNil(t.nextTransition(from: date(10, 3, 0)))
    }

    // MARK: Daylight saving

    /// On 2026-10-25 Paris repeats 02:00-03:00. Windows are wall-clock, so both passes of
    /// the repeated hour must read as the same band.
    func testRepeatedHourDuringDSTFallback() {
        var t = Tariff()
        t.mode = .peakOffPeak
        t.offPeakRate = 0.10
        t.peakRate = 0.20
        t.offPeakWindows = Tariff.parseWindows("00:00-08:00")!

        XCTAssertTrue(t.isOffPeak(at: date(25, 2, 30, month: 10)))
        XCTAssertFalse(t.isOffPeak(at: date(25, 9, 0, month: 10)))
    }

    /// On 2026-03-29 Paris skips 02:00-03:00. Asking for 02:30 yields the shifted instant;
    /// the band decision must stay with whatever the local clock reads.
    func testMissingHourDuringDSTGap() {
        var t = Tariff()
        t.mode = .peakOffPeak
        t.offPeakRate = 0.10
        t.peakRate = 0.20
        t.offPeakWindows = Tariff.parseWindows("00:00-08:00")!

        let when = date(29, 2, 30, month: 3)
        XCTAssertEqual(paris.dateComponents([.hour, .minute], from: when).hour, 3, "02:30 does not exist, expect it to shift")
        XCTAssertTrue(t.isOffPeak(at: when))
    }

    /// The calendar is a parameter for a reason: a travelling laptop prices the tariff of
    /// wherever it currently is.
    func testInjectedCalendarUsesItsOwnWallClock() {
        var t = Tariff()
        t.mode = .peakOffPeak
        t.offPeakWindows = Tariff.parseWindows("00:00-08:00")!

        var ny = paris
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        XCTAssertTrue(t.isOffPeak(at: date(1, 2, 30, month: 11, calendar: ny), calendar: ny))
    }

    // MARK: Parsing — a typo must never silently change a bill

    func testRejectsUnreadableSchedules() {
        XCTAssertNil(Tariff.parseWindows(""))
        XCTAssertNil(Tariff.parseWindows("night"))
        XCTAssertNil(Tariff.parseWindows("25:00-06:00"))
        XCTAssertNil(Tariff.parseWindows("22:70-06:00"))
        XCTAssertNil(Tariff.parseWindows("22:00"))
        XCTAssertNil(Tariff.parseWindows("22:00 06:00"))
        XCTAssertNil(Tariff.parseWindows("7am-9pm"))
        // One bad entry poisons the list: applying a partial schedule would be worse than
        // applying none.
        XCTAssertNil(Tariff.parseWindows("22:00-06:00, 7am-9pm"))
    }

    func testAcceptsReasonableInputVariations() {
        XCTAssertEqual(Tariff.parseWindows("22:00-06:00")?.count, 1)
        XCTAssertEqual(Tariff.parseWindows("22:00-06:00, 14:00-16:00")?.count, 2)
        XCTAssertEqual(Tariff.parseWindows("22:00-06:00; 14:00-16:00")?.count, 2)
        XCTAssertEqual(Tariff.parseWindows(" 22:00 - 06:00 ")?.count, 1)
        XCTAssertEqual(Tariff.parseWindows("22:00-06:00, 22:00-06:00")?.count, 2)
    }

    /// What the settings field shows must parse back to the same schedule.
    func testWindowTextRoundTrips() {
        let text = "00:50-06:50, 14:50-16:50"
        XCTAssertEqual(Tariff.windowsText(Tariff.parseWindows(text)!), text)
    }

    func testDefaultsAreFlatAndUsable() {
        let t = Tariff()
        XCTAssertEqual(t.mode, .flat)
        XCTAssertFalse(t.isTimeOfUse)
        XCTAssertFalse(t.isOffPeak(at: date(10, 3, 0)))
        XCTAssertEqual(t.rate(at: date(10, 3, 0)), t.peakRate, accuracy: 0.0001)
    }

    // MARK: Money formatting

    func testRateTextTrimsZerosButKeepsTwoDecimals() {
        XCTAssertEqual(Money.rateText(0.12), "0.12")
        XCTAssertEqual(Money.rateText(0.1), "0.10")
        XCTAssertEqual(Money.rateText(0.2), "0.20")
        XCTAssertEqual(Money.rateText(0.214), "0.214")
        XCTAssertEqual(Money.rateText(0.1234), "0.1234")
        XCTAssertEqual(Money.rateText(1.5), "1.50")
        XCTAssertEqual(Money.rateText(0), "0.00")
        XCTAssertEqual(Money.rateText(-1), "0.00", "a negative rate has no business reaching the UI")
    }

    /// The lowest rate a bill can carry is finer than a cent; rounding it away would make
    /// two different tariffs look identical.
    func testRateTextKeepsSubCentPrecision() {
        XCTAssertNotEqual(Money.rateText(0.1589), Money.rateText(0.1590))
        XCTAssertEqual(Money.rate(0.1589, .eur), "0.1589 €/kWh")
    }

    func testMinorUnitFormatting() {
        XCTAssertEqual(Money.minor(0.245, .usd), "24.5¢")
        XCTAssertEqual(Money.minor(0.031, .gbp), "3.1p")
        XCTAssertEqual(Money.minor(0, .eur), "0.0c")
    }

    func testEveryCurrencyHasBothSymbols() {
        for currency in Currency.allCases {
            XCTAssertFalse(currency.symbol.isEmpty)
            XCTAssertFalse(currency.minorSymbol.isEmpty)
        }
    }

    /// The settings picker is built from allCases, so a duplicate raw value would be a
    /// runtime hazard, not just a smell.
    func testCurrencyCasesAreDistinct() {
        XCTAssertEqual(Set(Currency.allCases.map(\.rawValue)).count, Currency.allCases.count)
    }

    private func clock(_ d: Date?) -> String {
        guard let d else { return "nil" }
        let f = DateFormatter()
        f.calendar = paris
        f.timeZone = paris.timeZone
        f.dateFormat = "dd-HH:mm"
        return f.string(from: d)
    }
}
