import Testing
import Foundation
@testable import AgentIsland

@Suite("SessionManager Sound Tests", .serialized)
struct SessionManagerSoundTests {

    @MainActor
    private func makeSettings() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "test-sms-\(UUID())")!)
    }

    private func makeSession(
        id: String = "s1",
        status: SessionStatus = .executing,
        title: String = "Test Task"
    ) -> AgentSession {
        AgentSession(
            id: id,
            agentType: .qoderWork,
            title: title,
            status: status,
            startTime: Date(),
            lastUpdate: Date(),
            terminalInfo: nil,
            currentToolCall: nil
        )
    }

    private func makeConfirmation(id: String = "c1") -> PendingConfirmation {
        PendingConfirmation(
            id: id,
            type: .permission,
            title: "Edit file",
            details: .permission(PermissionDetails(
                operation: "edit", diff: [], additions: 1, deletions: 0
            )),
            timestamp: Date()
        )
    }

    @Test("pollOnce triggers sessionStart sound for new session")
    @MainActor
    func pollOnceTriggersSessionStart() async {
        let mock = MockAgentAdaptor()
        let soundPlayer = MockSoundPlayer()
        let manager = SessionManager(adaptors: [mock], settingsStore: makeSettings(), soundPlayer: soundPlayer)

        await mock.setAvailable(true)
        await mock.setSessions([])
        await mock.setUseSessionOwnStatus(true)
        await manager.pollOnce()
        #expect(soundPlayer.playedEvents.isEmpty)

        await mock.setSessions([makeSession(id: "s1", status: .executing)])
        await manager.pollOnce()

        #expect(soundPlayer.playedEvents.contains(.sessionStart))
    }

    @Test("respond allow triggers confirmationApproved")
    @MainActor
    func respondAllowTriggersApproved() async throws {
        let mock = MockAgentAdaptor()
        let soundPlayer = MockSoundPlayer()
        let manager = SessionManager(adaptors: [mock], settingsStore: makeSettings(), soundPlayer: soundPlayer)
        await mock.setAvailable(true)
        await mock.setSessions([])
        await mock.setUseSessionOwnStatus(true)

        let session = makeSession()
        let confirmation = makeConfirmation()

        try await manager.respond(session: session, confirmation: confirmation, response: .allow)

        #expect(soundPlayer.playedEvents.contains(.confirmationApproved))
    }

    @Test("respond deny triggers confirmationDenied")
    @MainActor
    func respondDenyTriggersDenied() async throws {
        let mock = MockAgentAdaptor()
        let soundPlayer = MockSoundPlayer()
        let manager = SessionManager(adaptors: [mock], settingsStore: makeSettings(), soundPlayer: soundPlayer)
        await mock.setAvailable(true)
        await mock.setSessions([])
        await mock.setUseSessionOwnStatus(true)

        let session = makeSession()
        let confirmation = makeConfirmation()

        try await manager.respond(session: session, confirmation: confirmation, response: .deny)

        #expect(soundPlayer.playedEvents.contains(.confirmationDenied))
    }

    @Test("respond select triggers confirmationApproved")
    @MainActor
    func respondSelectTriggersApproved() async throws {
        let mock = MockAgentAdaptor()
        let soundPlayer = MockSoundPlayer()
        let manager = SessionManager(adaptors: [mock], settingsStore: makeSettings(), soundPlayer: soundPlayer)
        await mock.setAvailable(true)
        await mock.setSessions([])
        await mock.setUseSessionOwnStatus(true)

        let session = makeSession()
        let confirmation = makeConfirmation()

        try await manager.respond(
            session: session,
            confirmation: confirmation,
            response: .select(optionId: "opt1")
        )

        #expect(soundPlayer.playedEvents.contains(.confirmationApproved))
    }

    @Test("pollOnce works without sound player")
    @MainActor
    func pollOnceWithoutSoundPlayer() async {
        let mock = MockAgentAdaptor()
        let manager = SessionManager(adaptors: [mock], settingsStore: makeSettings())
        await mock.setAvailable(true)
        await mock.setSessions([makeSession()])
        await mock.setUseSessionOwnStatus(true)

        await manager.pollOnce()
        await manager.pollOnce()

        #expect(manager.sessions.count == 1)
    }
}
