import SwiftUI

struct SettingsSidebarView: View {
    @Binding var selection: SettingsSection

    var body: some View {
        List(selection: $selection) {
            sectionGroup(.main)
            Section("高级") {
                sectionGroup(.advanced)
            }
            Section("Agent Island") {
                sectionGroup(.app)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func sectionGroup(_ group: SettingsGroup) -> some View {
        ForEach(SettingsSection.sections(in: group)) { section in
            Label {
                Text(section.title)
            } icon: {
                Image(systemName: section.icon)
                    .foregroundStyle(section.iconColor)
            }
            .tag(section)
        }
    }
}
