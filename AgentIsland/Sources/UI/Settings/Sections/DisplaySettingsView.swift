import SwiftUI

struct DisplaySettingsView: View {
    @Bindable var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("显示").font(.title2.bold())

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "刘海区")
                    displayModeCards
                    SettingsPickerRow(
                        title: "显示器",
                        selection: $store.monitorSelection,
                        options: [(label: "主显示器", value: 0), (label: "副显示器", value: 1)]
                    )
                }
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "面板")
                    SettingsSliderRow(
                        title: "字体大小",
                        value: Binding(
                            get: { Double(store.panelFontSize) },
                            set: { store.panelFontSize = CGFloat($0) }
                        ),
                        range: 9...16,
                        step: 1,
                        unit: "pt"
                    )
                    SettingsSliderRow(
                        title: "完成卡片高度",
                        value: Binding(
                            get: { Double(store.completionCardHeight) },
                            set: { store.completionCardHeight = CGFloat($0) }
                        ),
                        range: 60...150,
                        step: 5,
                        unit: "pt"
                    )
                    SettingsSliderRow(
                        title: "面板最大高度",
                        value: Binding(
                            get: { Double(store.maxPanelHeight) },
                            set: { store.maxPanelHeight = CGFloat($0) }
                        ),
                        range: 300...800,
                        step: 10,
                        unit: "pt"
                    )
                    SettingsSliderRow(
                        title: "面板最大宽度",
                        value: Binding(
                            get: { Double(store.maxPanelWidth) },
                            set: { store.maxPanelWidth = CGFloat($0) }
                        ),
                        range: 400...900,
                        step: 10,
                        unit: "pt"
                    )
                }
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "微调")
                    SettingsSliderRow(
                        title: "刘海宽度偏移",
                        value: Binding(
                            get: { Double(store.notchWidthOffset) },
                            set: { store.notchWidthOffset = CGFloat($0) }
                        ),
                        range: -50...50,
                        step: 1,
                        unit: "pt"
                    )
                    SettingsSliderRow(
                        title: "刘海高度偏移",
                        value: Binding(
                            get: { Double(store.notchHeightOffset) },
                            set: { store.notchHeightOffset = CGFloat($0) }
                        ),
                        range: -20...20,
                        step: 1,
                        unit: "pt"
                    )
                }
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "子代理")
                    SettingsToggleRow(
                        title: "显示子代理详情",
                        isOn: $store.showSubAgentDetails,
                        subtitle: "在会话列表中展开子代理任务"
                    )
                }
                .padding(8)
            }
        }
    }

    private var displayModeCards: some View {
        HStack(spacing: 12) {
            ForEach(DisplayMode.allCases, id: \.self) { mode in
                displayModeCard(mode)
            }
        }
    }

    private func displayModeCard(_ mode: DisplayMode) -> some View {
        let isSelected = store.displayMode == mode
        return VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                .frame(height: 48)
                .overlay(
                    Text(mode == .compact ? "紧凑" : "详细")
                        .font(.system(size: 12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                )
            Text(mode == .compact ? "Compact" : "Detailed")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .onTapGesture { store.displayMode = mode }
    }
}
