import Foundation

enum HookInstaller {
    static let bridgeInstallPath = NSHomeDirectory() + "/.agent-island/bin/agent-island-bridge"
    private static let claudeSettingsPath = NSHomeDirectory() + "/.claude/settings.json"
    private static let hookIdentifier = "agent-island"

    static func ensureHooksInstalled() throws {
        try installBridgeScript()
        try registerHook()
    }

    static func installBridgeScript() throws {
        let binDir = (bridgeInstallPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: binDir, withIntermediateDirectories: true)

        guard let bridgeURL = Bundle.main.url(forResource: "agent-island-bridge", withExtension: nil) else {
            let script = Self.fallbackBridgeScript
            try script.write(toFile: bridgeInstallPath, atomically: true, encoding: .utf8)
            try setExecutable(bridgeInstallPath)
            return
        }
        try FileManager.default.copyItem(at: bridgeURL, to: URL(fileURLWithPath: bridgeInstallPath))
        try setExecutable(bridgeInstallPath)
    }

    static func registerHook() throws {
        try registerHook(settingsPath: claudeSettingsPath)
    }

    static func registerHook(settingsPath: String) throws {
        let fm = FileManager.default
        var settings: [String: Any]
        if fm.fileExists(atPath: settingsPath),
           let data = fm.contents(atPath: settingsPath),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = parsed
        } else {
            settings = [:]
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var permissionHooks = hooks["PermissionRequest"] as? [[String: Any]] ?? []

        let alreadyInstalled = permissionHooks.contains { entry in
            guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
            return entryHooks.contains { hook in
                guard let command = hook["command"] as? String else { return false }
                return command.contains(hookIdentifier)
            }
        }

        guard !alreadyInstalled else { return }

        let newEntry: [String: Any] = [
            "matcher": "*",
            "hooks": [[
                "type": "command",
                "command": bridgeInstallPath,
                "timeout": 86400
            ]]
        ]
        permissionHooks.insert(newEntry, at: 0)
        hooks["PermissionRequest"] = permissionHooks
        settings["hooks"] = hooks

        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: settingsPath))
    }

    static func isHookInstalled(settingsPath: String? = nil) -> Bool {
        let path = settingsPath ?? claudeSettingsPath
        guard let data = FileManager.default.contents(atPath: path),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = settings["hooks"] as? [String: Any],
              let permHooks = hooks["PermissionRequest"] as? [[String: Any]] else {
            return false
        }
        return permHooks.contains { entry in
            guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
            return entryHooks.contains { ($0["command"] as? String)?.contains(hookIdentifier) == true }
        }
    }

    private static func setExecutable(_ path: String) throws {
        var attrs = try FileManager.default.attributesOfItem(atPath: path)
        let perms = (attrs[.posixPermissions] as? Int) ?? 0o644
        attrs[.posixPermissions] = perms | 0o111
        try FileManager.default.setAttributes(attrs, ofItemAtPath: path)
    }

    private static let fallbackBridgeScript = """
    #!/bin/zsh
    SOCK="/tmp/agent-island.sock"
    FALLBACK='{"decision":"ask"}'
    [ ! -S "$SOCK" ] && { echo "$FALLBACK"; exit 0; }
    INPUT=$(cat)
    if command -v socat >/dev/null 2>&1; then
      RESPONSE=$(echo "$INPUT" | socat -t 30 - UNIX-CONNECT:"$SOCK" 2>/dev/null) || { echo "$FALLBACK"; exit 0; }
    else
      RESPONSE=$(echo "$INPUT" | nc -U -w 30 "$SOCK" 2>/dev/null) || { echo "$FALLBACK"; exit 0; }
    fi
    [ -n "$RESPONSE" ] && echo "$RESPONSE" || echo "$FALLBACK"
    """
}
