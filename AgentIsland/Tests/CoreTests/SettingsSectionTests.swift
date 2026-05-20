import Testing
@testable import AgentIsland

@Suite("SettingsSection Tests")
struct SettingsSectionTests {

    @Test("all sections have unique ids")
    func uniqueIds() {
        let ids = SettingsSection.allCases.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("all sections have non-empty title")
    func nonEmptyTitles() {
        for section in SettingsSection.allCases {
            #expect(!section.title.isEmpty)
        }
    }

    @Test("grouping produces three groups with correct members")
    func grouping() {
        let main = SettingsSection.sections(in: .main)
        let advanced = SettingsSection.sections(in: .advanced)
        let app = SettingsSection.sections(in: .app)
        #expect(main.count == 6)
        #expect(advanced.count == 3)
        #expect(app.count == 2)
        #expect(main.count + advanced.count + app.count == SettingsSection.allCases.count)
    }
}
