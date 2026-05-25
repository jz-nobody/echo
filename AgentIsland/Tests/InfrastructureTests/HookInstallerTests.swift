import Testing
import Foundation
@testable import AgentIsland

@Suite("HookInstaller Tests")
struct HookInstallerTests {

    private func tempSettingsPath() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hook-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json").path
    }

    @Test("registerHook adds all hook types to empty settings")
    func registerHookEmpty() throws {
        let path = tempSettingsPath()
        try "{}".write(toFile: path, atomically: true, encoding: .utf8)

        try HookInstaller.registerHook(settingsPath: path)

        #expect(HookInstaller.isHookInstalled(settingsPath: path) == true)

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let settings = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]

        for (hookType, expectedTimeout) in HookInstaller.requiredHookTypes {
            let entries = hooks[hookType] as! [[String: Any]]
            #expect(entries.count == 1, "Expected 1 entry for \(hookType)")
            let hookEntry = (entries[0]["hooks"] as! [[String: Any]]).first!
            #expect(hookEntry["timeout"] as? Int == expectedTimeout)
            #expect((hookEntry["command"] as? String)?.contains("agent-island") == true)
        }
    }

    @Test("registerHook is idempotent")
    func registerHookIdempotent() throws {
        let path = tempSettingsPath()
        try "{}".write(toFile: path, atomically: true, encoding: .utf8)

        try HookInstaller.registerHook(settingsPath: path)
        try HookInstaller.registerHook(settingsPath: path)

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let settings = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]

        for (hookType, _) in HookInstaller.requiredHookTypes {
            let entries = hooks[hookType] as! [[String: Any]]
            #expect(entries.count == 1, "\(hookType) should have exactly 1 entry after idempotent install")
        }
    }

    @Test("registerHook preserves existing hooks")
    func registerHookPreservesExisting() throws {
        let path = tempSettingsPath()
        let existing: [String: Any] = [
            "env": ["KEY": "VALUE"],
            "hooks": [
                "PermissionRequest": [[
                    "matcher": "*",
                    "hooks": [["type": "command", "command": "other-tool", "timeout": 10]]
                ]],
                "PostToolUse": [[
                    "hooks": [["type": "command", "command": "logger"]]
                ]]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: existing)
        try data.write(to: URL(fileURLWithPath: path))

        try HookInstaller.registerHook(settingsPath: path)

        let updated = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: path))
        ) as! [String: Any]

        let env = updated["env"] as? [String: String]
        #expect(env?["KEY"] == "VALUE")

        let hooks = updated["hooks"] as! [String: Any]
        let permHooks = hooks["PermissionRequest"] as! [[String: Any]]
        #expect(permHooks.count == 2)

        let postHooks = hooks["PostToolUse"] as! [[String: Any]]
        #expect(postHooks.count == 2)

        let loggerEntry = postHooks.first { entry in
            guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
            return entryHooks.contains { ($0["command"] as? String) == "logger" }
        }
        #expect(loggerEntry != nil)
    }

    @Test("isHookInstalled returns false for no settings file")
    func isHookInstalledNoFile() {
        let result = HookInstaller.isHookInstalled(settingsPath: "/nonexistent/path/settings.json")
        #expect(result == false)
    }

    @Test("registerHook creates settings when file does not exist")
    func registerHookCreatesFile() throws {
        let path = tempSettingsPath()
        // Don't create the file

        try HookInstaller.registerHook(settingsPath: path)

        #expect(HookInstaller.isHookInstalled(settingsPath: path) == true)
    }
}
