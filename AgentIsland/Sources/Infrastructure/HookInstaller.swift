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

        let fm = FileManager.default
        let dest = URL(fileURLWithPath: bridgeInstallPath)

        let candidates: [URL?] = [
            Bundle.main.url(forResource: "agent-island-bridge", withExtension: nil),
            Bundle.main.executableURL.map {
                $0.deletingLastPathComponent().appendingPathComponent("agent-island-bridge")
            },
        ]

        for case let url? in candidates where fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: dest)
            try fm.copyItem(at: url, to: dest)
            try setExecutable(bridgeInstallPath)
            return
        }

        let script = Self.fallbackBridgeScript
        try script.write(toFile: bridgeInstallPath, atomically: true, encoding: .utf8)
        try setExecutable(bridgeInstallPath)
    }

    static func registerHook() throws {
        try registerHook(settingsPath: claudeSettingsPath)
    }

    static let requiredHookTypes: [(type: String, timeout: Int)] = [
        ("PermissionRequest", 86400),
        ("PreToolUse", 5),
        ("PostToolUse", 5),
        ("UserPromptSubmit", 5),
        ("PreCompact", 5),
        ("Stop", 5),
    ]

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

        let allInstalled = requiredHookTypes.allSatisfy { hookType, _ in
            guard let entries = hooks[hookType] as? [[String: Any]] else { return false }
            return entries.contains { entry in
                guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
                return entryHooks.contains { ($0["command"] as? String)?.contains(hookIdentifier) == true }
            }
        }
        guard !allInstalled else { return }

        for (hookType, timeout) in requiredHookTypes {
            var entries = hooks[hookType] as? [[String: Any]] ?? []

            entries.removeAll { entry in
                guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
                return entryHooks.contains { ($0["command"] as? String)?.contains(hookIdentifier) == true }
            }

            let newEntry: [String: Any] = [
                "matcher": "*",
                "hooks": [[
                    "type": "command",
                    "command": bridgeInstallPath,
                    "timeout": timeout,
                ] as [String: Any]],
            ]
            entries.insert(newEntry, at: 0)
            hooks[hookType] = entries
        }

        settings["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: settingsPath))
    }

    static func isHookInstalled(settingsPath: String? = nil) -> Bool {
        let path = settingsPath ?? claudeSettingsPath
        guard let data = FileManager.default.contents(atPath: path),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = settings["hooks"] as? [String: Any] else {
            return false
        }
        return requiredHookTypes.allSatisfy { hookType, _ in
            guard let entries = hooks[hookType] as? [[String: Any]] else { return false }
            return entries.contains { entry in
                guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
                return entryHooks.contains { ($0["command"] as? String)?.contains(hookIdentifier) == true }
            }
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
    RESPONSE=$(printf '%s' "$INPUT" | python3 -c '
    import socket, sys, json
    data = sys.stdin.buffer.read()
    hook_type = json.loads(data).get("hook_event_name", "")
    timeout = 86400 if hook_type == "PermissionRequest" else 45
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    try:
        sock.connect("/tmp/agent-island.sock")
        sock.sendall(data)
        sock.shutdown(socket.SHUT_WR)
        resp = b""
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            resp += chunk
        sys.stdout.buffer.write(resp)
    except Exception:
        pass
    finally:
        sock.close()
    ' 2>/dev/null) || RESPONSE=""
    [ -n "$RESPONSE" ] && echo "$RESPONSE" || echo "$FALLBACK"
    """
}
