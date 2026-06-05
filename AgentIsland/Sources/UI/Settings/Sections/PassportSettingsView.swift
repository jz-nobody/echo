import SwiftUI

struct PassportSettingsView: View {
    let trialManager: TrialManager
    @State private var tokenInput = ""
    @State private var activationMessage: String?
    @State private var activationSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(title: "通行证")

            statusCard

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("激活")
                        .font(.headline)
                    Text("输入开发者提供的token进行激活")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        SecureField("输入token", text: $tokenInput)
                            .textFieldStyle(.roundedBorder)

                        Button("激活") {
                            activateToken()
                        }
                        .disabled(tokenInput.isEmpty)
                    }

                    if let message = activationMessage {
                        Text(message)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(activationSuccess ? .green : .red)
                    }
                }
                .padding(4)
            }
        }
    }

    private var statusCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("当前状态")
                        .font(.headline)
                    Spacer()
                    statusBadge
                }

                Divider()

                if let install = trialManager.installDate {
                    infoRow("安装日期", value: dateString(install))
                }

                if let activation = trialManager.activationDate {
                    infoRow("激活日期", value: dateString(activation))
                }

                infoRow("剩余天数", value: daysLeftText)
            }
            .padding(4)
        }
    }

    private var statusBadge: some View {
        Text(statusText)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.15))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }

    private var statusText: String {
        switch trialManager.status {
        case .trial: "试用中"
        case .expired: "已过期"
        case .activated: "已激活"
        case .activationExpired: "授权过期"
        }
    }

    private var statusColor: Color {
        switch trialManager.status {
        case .trial: .blue
        case .expired: .red
        case .activated: .green
        case .activationExpired: .orange
        }
    }

    private var daysLeftText: String {
        switch trialManager.status {
        case .trial(let days): "\(days) 天"
        case .activated(let days): "\(days) 天"
        case .expired, .activationExpired: "0 天"
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.system(size: 13))
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func activateToken() {
        let success = trialManager.activate(token: tokenInput.trimmingCharacters(in: .whitespacesAndNewlines))
        activationSuccess = success
        activationMessage = success ? "激活成功" : "token无效，请重试"
        if success { tokenInput = "" }
    }
}
