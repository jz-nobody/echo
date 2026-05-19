import SwiftUI

struct ExpandedPanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Sessions")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)

            Text("No active tasks")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(DesignTokens.textSecondary)

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: DesignTokens.panelMaxWidth, minHeight: 120)
        .background(DesignTokens.panelBackground)
        .clipShape(
            RoundedRectangle(cornerRadius: DesignTokens.panelCornerRadius, style: .continuous)
        )
        .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 4)
    }
}

#Preview {
    ExpandedPanelView()
        .padding()
        .background(Color.gray.opacity(0.2))
}
