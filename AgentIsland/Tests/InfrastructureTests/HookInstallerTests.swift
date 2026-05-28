import Testing
import Foundation
@testable import AgentIsland

@Suite("HookInstaller Tests")
struct HookInstallerTests {

    private func tempSettingsPath(prefix: String = "hook-test") -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json").path
    }

    // MARK: - Shared Assertion Helpers

    private func assertRegisterOnEmpty(config: HookInstaller.AgentHookConfig) throws {
        let path = tempSettingsPath(prefix: config.source)
        try "{}".write(toFile: path, atomically: true, encoding: .utf8)

        try HookInstaller.registerHooks(config: config, settingsPath: path)

        #expect(HookInstaller.isHookInstalled(config: config, settingsPath: path) == true)

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let settings = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]

        for (hookType, expectedTimeout) in config.hookTypes {
            let entries = hooks[hookType] as! [[String: Any]]
            #expect(entries.count == 1, "Expected 1 entry for \(hookType)")
            #expect(entries[0]["matcher"] as? String == "*", "\(hookType) should have matcher '*'")
            let hookEntry = (entries[0]["hooks"] as! [[String: Any]]).first!
            #expect(hookEntry["timeout"] as? Int == expectedTimeout)
            let command = hookEntry["command"] as? String
            #expect(command?.contains("agent-island") == true)
            #expect(command?.contains("--source \(config.source)") == true)
        }
    }

    private func assertIdempotent(config: HookInstaller.AgentHookConfig) throws {
        let path = tempSettingsPath(prefix: config.source)
        try "{}".write(toFile: path, atomically: true, encoding: .utf8)

        try HookInstaller.registerHooks(config: config, settingsPath: path)
        try HookInstaller.registerHooks(config: config, settingsPath: path)

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let settings = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]

        for (hookType, _) in config.hookTypes {
            let entries = hooks[hookType] as! [[String: Any]]
            #expect(entries.count == 1, "\(hookType) should have exactly 1 entry after idempotent install")
        }
    }

    // MARK: - Claude Code Tests

    @Test("registerHooks adds all hook types for claude")
    func registerHooksClaude() throws {
        try assertRegisterOnEmpty(config: HookInstaller.agentConfigs[0])
    }

    @Test("registerHooks is idempotent for claude")
    func registerHooksClaudeIdempotent() throws {
        try assertIdempotent(config: HookInstaller.agentConfigs[0])
    }

    @Test("registerHooks preserves existing hooks for claude")
    func registerHooksClaudePreservesExisting() throws {
        let path = tempSettingsPath(prefix: "claude")
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

        try HookInstaller.registerHooks(config: HookInstaller.agentConfigs[0], settingsPath: path)

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

    @Test("registerHooks creates settings when file does not exist")
    func registerHooksCreatesFile() throws {
        let path = tempSettingsPath(prefix: "claude")
        try HookInstaller.registerHooks(config: HookInstaller.agentConfigs[0], settingsPath: path)
        #expect(HookInstaller.isHookInstalled(config: HookInstaller.agentConfigs[0], settingsPath: path) == true)
    }

    // MARK: - Codex Tests

    @Test("registerHooks adds all hook types for codex")
    func registerHooksCodex() throws {
        try assertRegisterOnEmpty(config: HookInstaller.agentConfigs[1])
    }

    @Test("registerHooks is idempotent for codex")
    func registerHooksCodexIdempotent() throws {
        try assertIdempotent(config: HookInstaller.agentConfigs[1])
    }

    @Test("registerHooks preserves existing hooks for codex")
    func registerHooksCodexPreservesExisting() throws {
        let path = tempSettingsPath(prefix: "codex")
        let existing: [String: Any] = [
            "hooks": [
                "PermissionRequest": [[
                    "hooks": [["type": "command", "command": "vibe-island-bridge --source codex", "timeout": 7200]]
                ]],
                "SessionStart": [[
                    "matcher": "startup|resume",
                    "hooks": [["type": "command", "command": "other-tool", "timeout": 45]]
                ]]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: existing)
        try data.write(to: URL(fileURLWithPath: path))

        try HookInstaller.registerHooks(config: HookInstaller.agentConfigs[1], settingsPath: path)

        let updated = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: path))
        ) as! [String: Any]
        let hooks = updated["hooks"] as! [String: Any]

        let permHooks = hooks["PermissionRequest"] as! [[String: Any]]
        #expect(permHooks.count == 2)

        let sessionHooks = hooks["SessionStart"] as! [[String: Any]]
        #expect(sessionHooks.count == 2)

        let otherToolEntry = sessionHooks.first { entry in
            guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
            return entryHooks.contains { ($0["command"] as? String) == "other-tool" }
        }
        #expect(otherToolEntry != nil)
    }

    // MARK: - QoderWork Tests

    @Test("registerHooks adds all hook types for qoderwork")
    func registerHooksQoderWork() throws {
        try assertRegisterOnEmpty(config: HookInstaller.agentConfigs[2])
    }

    @Test("registerHooks is idempotent for qoderwork")
    func registerHooksQoderWorkIdempotent() throws {
        try assertIdempotent(config: HookInstaller.agentConfigs[2])
    }

    @Test("registerHooks preserves existing hooks for qoderwork")
    func registerHooksQoderWorkPreservesExisting() throws {
        let path = tempSettingsPath(prefix: "qoderwork")
        let existing: [String: Any] = [
            "hooks": [
                "PreToolUse": [[
                    "matcher": "*",
                    "hooks": [["type": "command", "command": "guard-tool.sh", "timeout": 10]]
                ]],
                "UserPromptSubmit": [[
                    "hooks": [["type": "command", "command": "guard-prompt.sh", "timeout": 15]]
                ]]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: existing)
        try data.write(to: URL(fileURLWithPath: path))

        try HookInstaller.registerHooks(config: HookInstaller.agentConfigs[2], settingsPath: path)

        let updated = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: path))
        ) as! [String: Any]
        let hooks = updated["hooks"] as! [String: Any]

        let preToolHooks = hooks["PreToolUse"] as! [[String: Any]]
        #expect(preToolHooks.count == 2)

        let firstEntry = preToolHooks[0]
        let firstHooks = firstEntry["hooks"] as! [[String: Any]]
        #expect((firstHooks[0]["command"] as? String)?.contains("agent-island") == true,
                "Agent Island hook should be first")
        #expect(firstEntry["matcher"] as? String == "*")

        let promptHooks = hooks["UserPromptSubmit"] as! [[String: Any]]
        #expect(promptHooks.count == 2)

        let guardEntry = preToolHooks.last { entry in
            guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
            return entryHooks.contains { ($0["command"] as? String) == "guard-tool.sh" }
        }
        #expect(guardEntry != nil)
    }

    // MARK: - Cross-Agent Tests

    @Test("isHookInstalled returns false for nonexistent file")
    func isHookInstalledNoFile() {
        for config in HookInstaller.agentConfigs {
            let result = HookInstaller.isHookInstalled(config: config, settingsPath: "/nonexistent/path/settings.json")
            #expect(result == false, "\(config.source) should return false for nonexistent file")
        }
    }

    @Test("registerHooks skips when requiresExistingDir and dir absent")
    func skipsWhenDirAbsent() throws {
        for config in HookInstaller.agentConfigs where config.requiresExistingDir {
            let path = "/nonexistent-dir-\(UUID().uuidString)/settings.json"
            try HookInstaller.registerHooks(config: config, settingsPath: path)
            #expect(HookInstaller.isHookInstalled(config: config, settingsPath: path) == false,
                    "\(config.source) should skip when dir absent")
        }
    }

    // MARK: - Migration Tests

    @Test("old hooks without --source detected as not installed")
    func oldFormatNotDetectedAsInstalled() throws {
        let config = HookInstaller.agentConfigs[0]
        let path = tempSettingsPath(prefix: "migration")
        var oldHooks: [String: Any] = [:]
        for (hookType, timeout) in config.hookTypes {
            oldHooks[hookType] = [[
                "matcher": "*",
                "hooks": [["type": "command",
                           "command": HookInstaller.bridgeInstallPath,
                           "timeout": timeout] as [String: Any]]
            ] as [String: Any]]
        }
        let data = try JSONSerialization.data(withJSONObject: ["hooks": oldHooks])
        try data.write(to: URL(fileURLWithPath: path))

        #expect(HookInstaller.isHookInstalled(config: config, settingsPath: path) == false,
                "Hooks without --source should not count as installed")
    }

    @Test("registerHooks upgrades old hooks to --source format")
    func upgradesOldFormat() throws {
        let config = HookInstaller.agentConfigs[0]
        let path = tempSettingsPath(prefix: "upgrade")
        var oldHooks: [String: Any] = [:]
        for (hookType, timeout) in config.hookTypes {
            oldHooks[hookType] = [[
                "matcher": "*",
                "hooks": [["type": "command",
                           "command": HookInstaller.bridgeInstallPath,
                           "timeout": timeout] as [String: Any]]
            ] as [String: Any]]
        }
        let data = try JSONSerialization.data(withJSONObject: ["hooks": oldHooks])
        try data.write(to: URL(fileURLWithPath: path))

        try HookInstaller.registerHooks(config: config, settingsPath: path)

        #expect(HookInstaller.isHookInstalled(config: config, settingsPath: path) == true)

        let updated = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: path))
        ) as! [String: Any]
        let hooks = updated["hooks"] as! [String: Any]
        for (hookType, _) in config.hookTypes {
            let entries = hooks[hookType] as! [[String: Any]]
            #expect(entries.count == 1, "\(hookType) should have 1 entry after upgrade (old removed)")
            let hookEntry = (entries[0]["hooks"] as! [[String: Any]]).first!
            let command = hookEntry["command"] as? String
            #expect(command?.contains("--source claude") == true)
        }
    }

    @Test("registerHooks fixes hooks missing matcher")
    func fixesHooksMissingMatcher() throws {
        let config = HookInstaller.agentConfigs[1]
        let path = tempSettingsPath(prefix: "codex-matcher-fix")
        var oldHooks: [String: Any] = [:]
        for (hookType, timeout) in config.hookTypes {
            oldHooks[hookType] = [[
                "hooks": [["type": "command",
                           "command": HookInstaller.bridgeInstallPath + " --source codex",
                           "timeout": timeout] as [String: Any]]
            ] as [String: Any]]
        }
        let data = try JSONSerialization.data(withJSONObject: ["hooks": oldHooks])
        try data.write(to: URL(fileURLWithPath: path))

        #expect(HookInstaller.isHookInstalled(config: config, settingsPath: path) == false,
                "Hooks without matcher should not count as installed")

        try HookInstaller.registerHooks(config: config, settingsPath: path)

        #expect(HookInstaller.isHookInstalled(config: config, settingsPath: path) == true)

        let updated = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: path))
        ) as! [String: Any]
        let hooks = updated["hooks"] as! [String: Any]
        for (hookType, _) in config.hookTypes {
            let entries = hooks[hookType] as! [[String: Any]]
            #expect(entries.count == 1, "\(hookType) should have 1 entry after fix")
            #expect(entries[0]["matcher"] as? String == "*", "\(hookType) should have matcher after fix")
        }
    }

    @Test("agent-island hook inserted at position 0")
    func hookInsertedFirst() throws {
        for config in HookInstaller.agentConfigs {
            let path = tempSettingsPath(prefix: config.source)
            let existing: [String: Any] = [
                "hooks": [
                    config.hookTypes[0].type: [[
                        "matcher": "*",
                        "hooks": [["type": "command", "command": "other-tool", "timeout": 10]]
                    ]]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: existing)
            try data.write(to: URL(fileURLWithPath: path))

            try HookInstaller.registerHooks(config: config, settingsPath: path)

            let updated = try JSONSerialization.jsonObject(
                with: Data(contentsOf: URL(fileURLWithPath: path))
            ) as! [String: Any]
            let hooks = updated["hooks"] as! [String: Any]
            let entries = hooks[config.hookTypes[0].type] as! [[String: Any]]
            let firstHooks = entries[0]["hooks"] as! [[String: Any]]
            #expect((firstHooks[0]["command"] as? String)?.contains("agent-island") == true,
                    "\(config.source): agent-island hook should be first")
        }
    }

    @Test("agentConfigs covers all expected sources")
    func configCoversAllSources() {
        let sources = HookInstaller.agentConfigs.map(\.source)
        #expect(sources.contains("claude"))
        #expect(sources.contains("codex"))
        #expect(sources.contains("qoderwork"))
    }
}
