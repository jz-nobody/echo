import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("通用").font(.title2.bold())

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "系统")
                    SettingsToggleRow(
                        title: "登录时打开",
                        isOn: $store.launchAtLogin,
                        subtitle: "系统启动时自动运行 Echo"
                    )
                }
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "展开")
                    SettingsToggleRow(
                        title: "鼠标悬浮展开",
                        isOn: $store.hoverToExpand
                    )
                    SettingsSliderRow(
                        title: "悬浮延迟",
                        value: $store.hoverDelay,
                        range: 0.05...1.0,
                        step: 0.05,
                        unit: "s"
                    )
                    SettingsToggleRow(
                        title: "智能抑制",
                        isOn: $store.smartSuppression,
                        subtitle: "全屏应用中减少干扰"
                    )
                }
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "显隐")
                    SettingsToggleRow(
                        title: "全屏时隐藏",
                        isOn: $store.hideInFullscreen
                    )
                    SettingsToggleRow(
                        title: "无活跃会话时隐藏",
                        isOn: $store.hideWhenNoActiveSessions
                    )
                }
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "收起")
                    SettingsToggleRow(
                        title: "鼠标离开时自动收起",
                        isOn: $store.autoCollapseOnMouseExit
                    )
                    SettingsSliderRow(
                        title: "自动提醒间隔",
                        value: $store.autoReminderDuration,
                        range: 1...30,
                        step: 1,
                        unit: "s"
                    )
                    SettingsToggleRow(
                        title: "点击外部关闭",
                        isOn: $store.dismissOnClickOutside
                    )
                }
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "交互")
                    SettingsToggleRow(
                        title: "Agent 协作自动展开",
                        isOn: $store.agentTeamAutoExpand
                    )
                    SettingsSliderRow(
                        title: "空闲清理间隔",
                        value: Binding(
                            get: { store.idleCleanupInterval / 3600 },
                            set: { store.idleCleanupInterval = $0 * 3600 }
                        ),
                        range: 0.5...24,
                        step: 0.5,
                        unit: "h"
                    )
                    SettingsToggleRow(
                        title: "禁用点击跳转",
                        isOn: $store.disableClickToJump
                    )
                }
                .padding(8)
            }
        }
    }
}
