import Foundation
@testable import AgentIsland

func makeMockBridgeServer() throws -> BridgeServer {
    let tmpDir = NSTemporaryDirectory() + UUID().uuidString
    try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
    let configs = [
        AgentConfig(
            agentType: .claudeCode, tag: "claude", displayName: "Claude Code",
            socketPath: tmpDir + "/claude.sock",
            hookSettingsPath: tmpDir + "/claude/settings.json",
            hookTypes: AgentConfig.claude.hookTypes,
            requiresExistingDir: false,
            idleTimeout: nil
        ),
        AgentConfig(
            agentType: .codex, tag: "codex", displayName: "Codex",
            socketPath: tmpDir + "/codex.sock",
            hookSettingsPath: tmpDir + "/nonexistent/hooks.json",
            hookTypes: AgentConfig.codex.hookTypes,
            requiresExistingDir: true,
            idleTimeout: 7200
        ),
        AgentConfig(
            agentType: .qoderWork, tag: "qoderwork", displayName: "QoderWork",
            socketPath: tmpDir + "/qoderwork.sock",
            hookSettingsPath: tmpDir + "/nonexistent/settings.json",
            hookTypes: AgentConfig.qoderWork.hookTypes,
            requiresExistingDir: true,
            idleTimeout: nil
        ),
    ]
    return try BridgeServer(configs: configs)
}

extension BridgeServer {
    func injectSession(_ session: AgentSession) {
        sessions[session.id] = session
        sessionStates[session.id] = SessionState(status: session.status)
    }

    func injectConfirmation(
        _ conf: PendingConfirmation,
        sessionId: String,
        respond: @escaping @Sendable (HookResponse) -> Void = { _ in }
    ) {
        pendingConfirmations[conf.id] = conf
        confirmationToSession[conf.id] = sessionId
        responseCallbacks[conf.id] = respond
    }
}
