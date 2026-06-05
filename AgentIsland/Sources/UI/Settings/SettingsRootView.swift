import SwiftUI

struct SettingsRootView: View {
    let store: SettingsStore
    let trialManager: TrialManager
    @State private var selectedSection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            SettingsSidebarView(selection: $selectedSection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            ScrollView {
                contentView(for: selectedSection)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 720, height: 560)
    }

    @ViewBuilder
    private func contentView(for section: SettingsSection) -> some View {
        switch section {
        case .general:
            GeneralSettingsView(store: store)
        case .display:
            DisplaySettingsView(store: store)
        case .sound:
            SoundSettingsView(store: store)
        case .about:
            AboutSettingsView()
        case .notification:
            NotificationSettingsView(store: store)
        case .passport:
            PassportSettingsView(trialManager: trialManager)
        default:
            PlaceholderSettingsView(section: section)
        }
    }
}
