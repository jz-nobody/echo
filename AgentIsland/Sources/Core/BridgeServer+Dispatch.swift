import Foundation

extension BridgeServer: IPCServerDelegate {

    nonisolated func ipcServer(
        _ server: IPCServer, didReceive message: HookMessage,
        clientPID: pid_t?, clientID: UUID,
        respond: @escaping @Sendable (HookResponse) -> Void
    ) {
        let tag = server.tag
        Task {
            await self.dispatchHook(
                message: message, tag: tag,
                clientPID: clientPID, clientID: clientID, respond: respond
            )
        }
    }

    nonisolated func ipcServer(_ server: IPCServer, clientDidDisconnect clientID: UUID) {
        Task { await self.handleClientDisconnect(clientID: clientID) }
    }

    func dispatchHook(
        message: HookMessage, tag: String,
        clientPID: pid_t?, clientID: UUID,
        respond: @escaping @Sendable (HookResponse) -> Void
    ) {
        NSLog("[BridgeServer] dispatchHook: tag=%@ type=%@ sessionId=%@ toolName=%@", tag, message.type, message.sessionId, message.toolName ?? "-")

        guard let config = agentConfigs[tag] else {
            respond(.empty)
            return
        }

        let agentType = config.agentType
        let sessionId = internalSessionId(agentType: agentType, hookSessionId: message.sessionId)

        if message.type == "PermissionRequest" {
            switch agentType {
            case .claudeCode:
                handleClaudePermissionRequest(
                    message: message, sessionId: sessionId,
                    clientID: clientID, respond: respond
                )
            case .qoderWork:
                handleQoderWorkPermissionRequest(
                    message: message, sessionId: sessionId,
                    clientPID: clientPID, clientID: clientID,
                    respond: respond
                )
            case .codex:
                handleCodexPermissionRequest(
                    message: message, sessionId: sessionId,
                    clientPID: clientPID, clientID: clientID,
                    respond: respond
                )
            default:
                handleGenericPermissionRequest(
                    message: message, sessionId: sessionId,
                    agentType: agentType, displayName: config.displayName,
                    clientID: clientID, respond: respond
                )
            }
            return
        }

        switch agentType {
        case .claudeCode:
            handleClaudeStatusHook(
                message: message, sessionId: sessionId, respond: respond
            )
        case .qoderWork:
            handleQoderWorkStatusHook(
                message: message, sessionId: sessionId,
                clientPID: clientPID, respond: respond
            )
        case .codex:
            handleCodexStatusHook(
                message: message, sessionId: sessionId,
                clientPID: clientPID, respond: respond
            )
        default:
            handleGenericStatusHook(
                message: message, sessionId: sessionId,
                agentType: agentType, displayName: config.displayName,
                respond: respond
            )
        }
    }
}
