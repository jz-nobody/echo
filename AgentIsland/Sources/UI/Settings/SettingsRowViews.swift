import SwiftUI

struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 8)
    }
}

struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var subtitle: String?

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

struct SettingsSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 13))
                Spacer()
                Text(formatValue())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
                .controlSize(.small)
        }
    }

    private func formatValue() -> String {
        if step >= 1 {
            return "\(Int(value))\(unit)"
        }
        return String(format: "%.2f\(unit)", value)
    }
}

struct SettingsPickerRow<T: Hashable>: View {
    let title: String
    @Binding var selection: T
    let options: [(label: String, value: T)]

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer()
            Picker("", selection: $selection) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}
