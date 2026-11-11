import SwiftUI

/// Editing the pricing model. Everything is validated on Apply: a rate or a window that
/// cannot be read is reported instead of being quietly dropped, because the whole point of
/// the feature is that these numbers end up in a cost total.
struct TariffSettingsSection: View {
    @ObservedObject var powerMonitor: PowerMonitorService

    @State private var mode: Tariff.Mode = .flat
    @State private var currency: Currency = .usd
    @State private var peakInput = ""
    @State private var offPeakInput = ""
    @State private var windowsInput = ""
    @State private var errorText: String?

    private var isTimeOfUse: Bool { mode == .peakOffPeak }

    var body: some View {
        SettingsSection(title: "Electricity Cost") {
            Picker("Pricing", selection: $mode) {
                Text("Flat rate").tag(Tariff.Mode.flat)
                Text("Peak / off-peak").tag(Tariff.Mode.peakOffPeak)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if isTimeOfUse {
                labeledField("Peak", text: $peakInput, prompt: "0.1200")
                labeledField("Off-peak", text: $offPeakInput, prompt: "0.0900")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Off-peak windows")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    TextField("22:00-06:00", text: $windowsInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .onSubmit { apply() }

                    Text("Local time, 24 h. A window that ends before it starts crosses midnight. Separate several windows with commas.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                labeledField("Rate", text: $peakInput, prompt: "0.120")
            }

            Picker("Currency", selection: $currency) {
                ForEach(Currency.allCases, id: \.self) { c in
                    Text("\(c.symbol)  \(c.rawValue.uppercased())").tag(c)
                }
            }
            .pickerStyle(.menu)
            .font(.system(size: 11))

            HStack(alignment: .top, spacing: 8) {
                Button("Apply") { apply() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Current: \(Money.rate(powerMonitor.tariff.rate(), powerMonitor.currency))/kWh")
                    .foregroundStyle(.green)
                if isTimeOfUse {
                    Text(powerMonitor.tariff.isOffPeak() ? "Now: off-peak" : "Now: peak")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11, weight: .medium))
        }
        .onAppear { sync() }
    }

    private func labeledField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)

            HStack(spacing: 3) {
                Text(currency.symbol)
                    .foregroundStyle(.secondary)
                TextField(prompt, text: text)
                    .textFieldStyle(.plain)
                    .frame(width: 52)
                    .onSubmit { apply() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )

            Text("per kWh")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }

    private func sync() {
        let tariff = powerMonitor.tariff
        mode = tariff.mode
        currency = powerMonitor.currency
        peakInput = Money.rateText(tariff.peakRate)
        offPeakInput = Money.rateText(tariff.offPeakRate)
        windowsInput = Tariff.windowsText(tariff.offPeakWindows)
        errorText = nil
    }

    private func apply() {
        guard let peak = parseRate(peakInput) else {
            errorText = "Enter a peak rate, e.g. 0.1200"
            return
        }

        // Start from the tariff in force so switching to flat does not discard an
        // off-peak schedule the user configured earlier.
        var tariff = powerMonitor.tariff
        tariff.mode = mode
        tariff.peakRate = peak

        if mode == .peakOffPeak {
            guard let offPeak = parseRate(offPeakInput) else {
                errorText = "Enter an off-peak rate, e.g. 0.0900"
                return
            }
            guard let windows = Tariff.parseWindows(windowsInput) else {
                errorText = "Windows as HH:mm-HH:mm, e.g. 22:00-06:00"
                return
            }
            tariff.offPeakRate = offPeak
            tariff.offPeakWindows = windows
        }

        errorText = nil
        powerMonitor.setTariff(tariff)
        powerMonitor.setCurrency(currency)
        sync()
    }

    /// Accepts both decimal separators — rates are copied off bills, which use whatever the
    /// country writes.
    private func parseRate(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0, value < 100 else { return nil }
        return value
    }
}
