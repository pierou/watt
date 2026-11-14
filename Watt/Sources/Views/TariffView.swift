import SwiftUI

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
