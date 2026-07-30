import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "island")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Echo")
                .font(.title.bold())

            Text("版本 0.1.0 (MVP)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Text("多 AI Agent 状态聚合器")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
