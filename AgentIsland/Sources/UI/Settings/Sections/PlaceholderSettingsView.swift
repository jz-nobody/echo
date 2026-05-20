import SwiftUI

struct PlaceholderSettingsView: View {
    let section: SettingsSection

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: section.icon)
                .font(.system(size: 36))
                .foregroundStyle(section.iconColor.opacity(0.5))
            Text(section.title)
                .font(.title2.bold())
            Text("Coming soon")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
