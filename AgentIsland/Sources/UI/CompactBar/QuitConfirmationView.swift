import SwiftUI

struct QuitConfirmationView: View {
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("是否确认关闭 Echo")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DesignTokens.textPrimary)

            HStack(spacing: 12) {
                Button("取消") { onCancel() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .foregroundStyle(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Button("确认") { onConfirm() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(DesignTokens.cardHover)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(24)
        .background(DesignTokens.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
