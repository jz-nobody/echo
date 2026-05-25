protocol AgentAdaptor: Sendable {
    var agentType: AgentType { get }
    var isAvailable: Bool { get async }
    func discoverSessions() async throws -> [AgentSession]
    func getStatus(session: AgentSession) async throws -> SessionStatus
    func getPendingConfirmations(session: AgentSession) async throws -> [PendingConfirmation]
    func respond(session: AgentSession, confirmation: PendingConfirmation, response: ConfirmationResponse) async throws
    func revokeAutoApprove(session: AgentSession) async
}

extension AgentAdaptor {
    func revokeAutoApprove(session: AgentSession) async {}
}
