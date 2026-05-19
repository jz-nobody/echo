import Foundation
@testable import AgentIsland

actor MockAgentAdaptor: AgentAdaptor {
    nonisolated let agentType: AgentType = .qoderWork
    var available = true
    var sessionsToReturn: [AgentSession] = []
    var statusToReturn: SessionStatus = .idle
    var confirmationsToReturn: [PendingConfirmation] = []
    var respondCalled = false
    var lastRespondResponse: ConfirmationResponse?

    var isAvailable: Bool { available }

    func discoverSessions() async throws -> [AgentSession] { sessionsToReturn }

    var useSessionOwnStatus = false

    func getStatus(session: AgentSession) async throws -> SessionStatus {
        useSessionOwnStatus ? session.status : statusToReturn
    }

    func getPendingConfirmations(session: AgentSession) async throws -> [PendingConfirmation] {
        confirmationsToReturn
    }

    func respond(
        session: AgentSession,
        confirmation: PendingConfirmation,
        response: ConfirmationResponse
    ) async throws {
        respondCalled = true
        lastRespondResponse = response
    }

    func setSessions(_ sessions: [AgentSession]) { self.sessionsToReturn = sessions }
    func setStatus(_ status: SessionStatus) { self.statusToReturn = status }
    func setAvailable(_ value: Bool) { self.available = value }
    func setConfirmations(_ confs: [PendingConfirmation]) { self.confirmationsToReturn = confs }
    func setUseSessionOwnStatus(_ value: Bool) { self.useSessionOwnStatus = value }
    func wasRespondCalled() -> Bool { respondCalled }
}
