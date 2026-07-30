import Foundation

struct AgentConfig: Sendable {
    let agentType: AgentType
    let tag: String
    let displayName: String
    let socketPath: String
    let hookSettingsPath: String
    let hookTypes: [(type: String, timeout: Int)]
    let requiresExistingDir: Bool
    let idleTimeout: TimeInterval?
}

extension AgentConfig {

    static let claude = AgentConfig(
        agentType: .claudeCode,
        tag: "claude",
        displayName: "Claude Code",
        socketPath: IPCProtocol.socketPath,
        hookSettingsPath: NSHomeDirectory() + "/.claude/settings.json",
        hookTypes: [
            ("PermissionRequest", 86400),
            ("PreToolUse", 5),
            ("PostToolUse", 5),
            ("UserPromptSubmit", 5),
            ("PreCompact", 5),
            ("Stop", 5),
            ("SessionStart", 5),
            ("StopFailure", 5),
            ("SubagentStart", 5),
            ("SubagentStop", 5),
        ],
        requiresExistingDir: false,
        idleTimeout: nil,
    )

    static let codex = AgentConfig(
        agentType: .codex,
        tag: "codex",
        displayName: "Codex",
        socketPath: "/tmp/agent-island-codex.sock",
        hookSettingsPath: NSHomeDirectory() + "/.codex/hooks.json",
        hookTypes: [
            ("PermissionRequest", 86400),
            ("PreToolUse", 5),
            ("PostToolUse", 5),
            ("UserPromptSubmit", 5),
            ("PreCompact", 5),
            ("Stop", 5),
            ("StopFailure", 5),
            ("SessionStart", 5),
            ("SubagentStart", 5),
            ("SubagentStop", 5),
        ],
        requiresExistingDir: true,
        idleTimeout: 7200
    )

    static let qoderWork = AgentConfig(
        agentType: .qoderWork,
        tag: "qoderwork",
        displayName: "QoderWork",
        socketPath: "/tmp/agent-island-qoderwork.sock",
        hookSettingsPath: NSHomeDirectory() + "/.qoderwork/settings.json",
        hookTypes: [
            ("PermissionRequest", 86400),
            ("SessionStart", 5),
            ("UserPromptSubmit", 5),
            ("PreToolUse", 5),
            ("PostToolUse", 5),
            ("Stop", 5),
        ],
        requiresExistingDir: true,
        idleTimeout: nil,
    )

    static let qoder = AgentConfig(
        agentType: .qoder,
        tag: "qoder",
        displayName: "Qoder",
        socketPath: "/tmp/agent-island-qoder.sock",
        hookSettingsPath: NSHomeDirectory() + "/.qoder/settings.json",
        hookTypes: [
            ("PermissionRequest", 86400),
            ("PreToolUse", 5),
            ("PostToolUse", 5),
            ("UserPromptSubmit", 5),
            ("PreCompact", 5),
            ("Stop", 5),
            ("SessionStart", 5),
            ("SubagentStart", 5),
            ("SubagentStop", 5),
        ],
        requiresExistingDir: true,
        idleTimeout: nil,
    )

    static let allDefaults: [AgentConfig] = [.claude, .codex, .qoderWork, .qoder]

    var hookConfig: HookInstaller.AgentHookConfig {
        HookInstaller.AgentHookConfig(
            source: tag,
            settingsPath: hookSettingsPath,
            hookTypes: hookTypes,
            requiresExistingDir: requiresExistingDir
        )
    }
}
