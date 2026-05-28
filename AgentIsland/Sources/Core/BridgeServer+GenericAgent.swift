import Foundation

extension BridgeServer {

    func handleGenericPermissionRequest(
        message: HookMessage, sessionId: String,
        agentType: AgentType, displayName: String,
        clientID: UUID,
        respond: @escaping @Sendable (HookResponse) -> Void
    ) {
        let id = internalSessionId(agentType: agentType, hookSessionId: message.sessionId)
        ensureSessionExists(id: id, agentType: agentType, title: displayName)
        recordActivity(sessionId: sessionId)
        handlePermissionRequest(
            message: message, sessionId: sessionId,
            clientID: clientID, respond: respond
        )
    }

    func handleGenericStatusHook(
        message: HookMessage, sessionId: String,
        agentType: AgentType, displayName: String,
        respond: @escaping @Sendable (HookResponse) -> Void
    ) {
        let id = internalSessionId(agentType: agentType, hookSessionId: message.sessionId)
        ensureSessionExists(id: id, agentType: agentType, title: displayName)
        recordActivity(sessionId: sessionId)

        guard let event = SessionEvent.from(
            hookType: message.type, toolName: message.toolName
        ) else {
            respond(.empty)
            return
        }

        if event.indicatesPostConfirmationProgress {
            clearStaleInteraction(for: sessionId)
        }

        applyEvent(event, sessionId: sessionId)
        respond(.empty)
    }

    func cleanupIdleSessions(agentType: AgentType, timeout: TimeInterval) {
        let now = Date()
        var toRemove: [String] = []
        for (id, session) in sessions where session.agentType == agentType {
            guard let lastActivity = lastActivityDates[id] else { continue }
            if now.timeIntervalSince(lastActivity) > timeout {
                toRemove.append(id)
            }
        }
        for id in toRemove {
            removeSession(id)
        }
    }
}
