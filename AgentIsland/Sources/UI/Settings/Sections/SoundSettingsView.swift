import SwiftUI

struct SoundSettingsView: View {
    @Bindable var store: SettingsStore

    private let soundOptions = [
        (label: "默认", value: "default"),
        (label: "无", value: "none"),
        (label: "叮咚", value: "chime"),
        (label: "提示", value: "alert"),
        (label: "气泡", value: "bubble"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("声音").font(.title2.bold())

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsToggleRow(
                        title: "启用声音",
                        isOn: $store.soundEnabled
                    )
                    SettingsSliderRow(
                        title: "音量",
                        value: Binding(
                            get: { Double(store.soundVolume) },
                            set: { store.soundVolume = Float($0) }
                        ),
                        range: 0...1,
                        step: 0.05
                    )
                }
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "会话")
                    soundEventRow("会话开始", binding: $store.soundSessionStart)
                    soundEventRow("会话结束", binding: $store.soundSessionEnd)
                }
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "交互")
                    soundEventRow("确认到达", binding: $store.soundConfirmationArrived)
                    soundEventRow("确认批准", binding: $store.soundConfirmationApproved)
                    soundEventRow("确认拒绝", binding: $store.soundConfirmationDenied)
                }
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "系统")
                    soundEventRow("错误", binding: $store.soundError)
                    soundEventRow("重连成功", binding: $store.soundReconnected)
                    soundEventRow("空闲提醒", binding: $store.soundIdleReminder)
                }
                .padding(8)
            }
        }
        .disabled(!store.soundEnabled)
    }

    private func soundEventRow(_ title: String, binding: Binding<String>) -> some View {
        SettingsPickerRow(
            title: title,
            selection: binding,
            options: soundOptions
        )
    }
}
