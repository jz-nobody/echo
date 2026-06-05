import SwiftUI

struct ActivationView: View {
    let trialManager: TrialManager
    @State private var tokenInput = ""
    @State private var errorMessage: String?
    @State private var isValidating = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                headerSection
                messageSection
                inputSection
                if let error = errorMessage {
                    errorLabel(error)
                }
                buttonSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity)
        .background(DesignTokens.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.panelCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.panelCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 4)
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(DesignTokens.statusWaiting)
                Text("产品升级")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DesignTokens.textPrimary)
            }
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(DesignTokens.cardBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var messageSection: some View {
        VStack(spacing: 8) {
            Text(statusMessage)
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)
            Text("请联系开发者获取token")
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.textSecondary.opacity(0.7))
        }
    }

    private var statusMessage: String {
        switch trialManager.status {
        case .expired:
            "试用到期"
        case .activationExpired:
            "授权已过期，请重新激活"
        default:
            "试用到期"
        }
    }

    private var inputSection: some View {
        SecureField("输入token", text: $tokenInput)
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .monospaced))
            .padding(10)
            .background(DesignTokens.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
            .foregroundStyle(DesignTokens.textPrimary)
            .onSubmit { validateToken() }
    }

    private func errorLabel(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DesignTokens.statusError)
            .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var buttonSection: some View {
        HStack(spacing: 12) {
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("关闭")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .background(DesignTokens.confirmationDenyBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                validateToken()
            } label: {
                Text("确认")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .foregroundStyle(DesignTokens.confirmationAllowText)
                    .background(tokenInput.isEmpty ? Color.gray : DesignTokens.confirmationAllowBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(tokenInput.isEmpty || isValidating)
        }
    }

    // MARK: - Actions

    private func validateToken() {
        guard !tokenInput.isEmpty else { return }
        isValidating = true
        errorMessage = nil

        let success = trialManager.activate(token: tokenInput.trimmingCharacters(in: .whitespacesAndNewlines))
        if success {
            errorMessage = nil
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                errorMessage = "token无效，请重试"
            }
            tokenInput = ""
        }
        isValidating = false
    }
}
