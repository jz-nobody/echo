import Foundation

enum HookInstaller {

    struct AgentHookConfig: Sendable {
        let source: String
        let settingsPath: String
        let hookTypes: [(type: String, timeout: Int)]
        let requiresExistingDir: Bool
    }

    static let bridgeInstallPath = NSHomeDirectory() + "/.agent-island/bin/agent-island-bridge"
    private static let hookIdentifier = "agent-island"

    static var agentConfigs: [AgentHookConfig] {
        AgentConfig.allDefaults.map(\.hookConfig)
    }

    static func ensureHooksInstalled() throws {
        try installBridge()
        for config in agentConfigs {
            try registerHooks(config: config)
        }
        cleanupOrphanedBridges()
    }

    static func installBridge() throws {
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

        try fallbackBridgeScript.write(toFile: bridgeInstallPath, atomically: true, encoding: .utf8)
        try setExecutable(bridgeInstallPath)
    }

    static func registerHooks(config: AgentHookConfig, settingsPath: String? = nil) throws {
        let path = settingsPath ?? config.settingsPath
        let fm = FileManager.default

        if config.requiresExistingDir {
            let dir = (path as NSString).deletingLastPathComponent
            guard fm.fileExists(atPath: dir) else { return }
        }

        var settings: [String: Any]
        if fm.fileExists(atPath: path),
           let data = fm.contents(atPath: path),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = parsed
        } else {
            settings = [:]
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        let command = "\(bridgeInstallPath) --source \(config.source)"

        let allInstalled = config.hookTypes.allSatisfy { hookType, _ in
            guard let entries = hooks[hookType] as? [[String: Any]] else { return false }
            return entries.contains { entry in
                guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
                let hasCommand = entryHooks.contains { hook in
                    guard let cmd = hook["command"] as? String else { return false }
                    return cmd.contains(hookIdentifier) && cmd.contains("--source")
                }
                let hasMatcher = entry["matcher"] != nil
                return hasCommand && hasMatcher
            }
        }
        guard !allInstalled else { return }

        for (hookType, timeout) in config.hookTypes {
            var entries = hooks[hookType] as? [[String: Any]] ?? []

            entries.removeAll { entry in
                guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
                return entryHooks.contains { ($0["command"] as? String)?.contains(hookIdentifier) == true }
            }

            let newEntry: [String: Any] = [
                "matcher": "*",
                "hooks": [[
                    "type": "command",
                    "command": command,
                    "timeout": timeout,
                ] as [String: Any]],
            ]
            entries.insert(newEntry, at: 0)
            hooks[hookType] = entries
        }

        settings["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
    }

    static func isHookInstalled(config: AgentHookConfig, settingsPath: String? = nil) -> Bool {
        let path = settingsPath ?? config.settingsPath
        guard let data = FileManager.default.contents(atPath: path),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = settings["hooks"] as? [String: Any] else {
            return false
        }
        return config.hookTypes.allSatisfy { hookType, _ in
            guard let entries = hooks[hookType] as? [[String: Any]] else { return false }
            return entries.contains { entry in
                guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
                let hasCommand = entryHooks.contains { hook in
                    guard let cmd = hook["command"] as? String else { return false }
                    return cmd.contains(hookIdentifier) && cmd.contains("--source")
                }
                let hasMatcher = entry["matcher"] != nil
                return hasCommand && hasMatcher
            }
        }
    }

    private static func cleanupOrphanedBridges() {
        let binDir = (bridgeInstallPath as NSString).deletingLastPathComponent
        let orphans = ["agent-island-bridge-codex", "agent-island-bridge-qoderwork"]
        for name in orphans {
            try? FileManager.default.removeItem(atPath: binDir + "/" + name)
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
    SOURCE="claude"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --source) SOURCE="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    case "$SOURCE" in
        claude)     SOCK="/tmp/agent-island.sock" ;;
        codex)      SOCK="/tmp/agent-island-codex.sock" ;;
        qoderwork)  SOCK="/tmp/agent-island-qoderwork.sock" ;;
        qoder)      SOCK="/tmp/agent-island-qoder.sock" ;;
        *)          printf '%s\\n' '{"decision":"ask"}'; exit 0 ;;
    esac
    FALLBACK='{"decision":"ask"}'
    [ ! -S "$SOCK" ] && { printf '%s\\n' "$FALLBACK"; exit 0; }
    INPUT=$(cat)
    RESPONSE=$(printf '%s' "$INPUT" | python3 -c '
    import socket, sys, json
    data = sys.stdin.buffer.read()
    hook_type = json.loads(data).get("hook_event_name", "")
    timeout = 86400 if hook_type == "PermissionRequest" else 45
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    try:
        sock.connect(sys.argv[1])
        sock.sendall(data)
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
    ' "$SOCK" 2>/dev/null) || RESPONSE=""
    [ -n "$RESPONSE" ] && printf '%s\\n' "$RESPONSE" || printf '%s\\n' "$FALLBACK"
    """
}
