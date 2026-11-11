import SwiftUI

/// Money display for the narrow stat columns. Amounts are stored in major units per kWh,
/// so a rate of 0.1750 means "0.1750 currency units per kWh".
enum Money {
    /// Rate as written on a bill, trailing zeros trimmed but never below two decimals:
    /// 0.12 -> "0.12", 0.1750 -> "0.175", 0.2000 -> "0.20".
    static func rateText(_ value: Double) -> String {
        let scaled = Int((max(0, value) * 10_000).rounded())
        var digits = String(format: "%04d", scaled % 10_000)
        while digits.count > 2, digits.hasSuffix("0") { digits.removeLast() }
        return "\(scaled / 10_000).\(digits)"
    }

    static func rate(_ value: Double, _ currency: Currency) -> String {
        "\(rateText(value)) \(currency.symbol)/kWh"
    }

    /// A cost in minor units, e.g. 24.5¢ or 3.1p.
    static func minor(_ amount: Double, _ currency: Currency) -> String {
        String(format: "%.1f%@", amount * 100, currency.minorSymbol)
    }
}

// MARK: - Rate now

/// The band in force right now, what it costs, and when it changes. Re-rendered by the
/// metering tick, so a band flip appears within a few seconds without extra timers.
struct RateSection: View {
    @ObservedObject var powerMonitor: PowerMonitorService

    var body: some View {
        let tariff = powerMonitor.tariff
        let offPeak = tariff.isOffPeak()

        NativeSectionView(title: "Tariff") {
            VStack(spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: offPeak ? "moon.stars.fill" : "sun.max.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(offPeak ? .indigo : .orange)
                        .frame(width: 16)

                    Text(offPeak ? "Off-peak hours" : "Peak hours")
                        .font(.system(size: 12, weight: .semibold))

                    Spacer()

                    Text(Money.rate(tariff.rate(), powerMonitor.currency))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }

                HStack(spacing: 6) {
                    Text(tariff.nextTransitionText ?? "")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(String(format: "%.0f%% of today", powerMonitor.todayOffPeakShare * 100))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 1)
        }
    }
}
