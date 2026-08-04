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
                toolName: "Edit", operation: "edit", diff: [], additions: 1, deletions: 0
            )),
            timestamp: Date()
        )
    }

    @Test("pollOnce triggers sessionStart sound for new session")
    @MainActor
    func pollOnceTriggersSessionStart() async throws {
        let server = try makeMockBridgeServer()
        let soundPlayer = MockSoundPlayer()
        let manager = SessionManager(bridgeServer: server, settingsStore: makeSettings(), soundPlayer: soundPlayer)

        await manager.pollOnce()
        #expect(soundPlayer.playedEvents.isEmpty)

        await server.injectSession(makeSession(id: "s1", status: .executing))
        await manager.pollOnce()

        #expect(soundPlayer.playedEvents.contains(.sessionStart))
    }

    @Test("status notification for hidden Codex subagent does not play completion")
    @MainActor
    func hiddenCodexSubagentNotificationDoesNotPlayCompletion() throws {
        let server = try makeMockBridgeServer()
        let soundPlayer = MockSoundPlayer()
        let manager = SessionManager(
            bridgeServer: server, settingsStore: makeSettings(), soundPlayer: soundPlayer
        )
        manager.startPolling()

        NotificationCenter.default.post(
            name: BridgeServer.statusChangedNotification,
            object: nil,
            userInfo: [
                "sessionId": "codex-hidden-child",
                "status": SessionStatus.idle,
                "previousStatus": SessionStatus.executing,
            ]
        )

        manager.stopPolling()
        #expect(!soundPlayer.playedEvents.contains(.runningCompleted))
    }

    @Test("completion transition is played once by polling")
    @MainActor
    func completionTransitionUsesSingleSoundPath() async throws {
        let server = try makeMockBridgeServer()
        let soundPlayer = MockSoundPlayer()
        let manager = SessionManager(
            bridgeServer: server, settingsStore: makeSettings(), soundPlayer: soundPlayer
        )
        await server.injectSession(makeSession(id: "visible-task", status: .executing))
        await manager.pollOnce()

        await server.injectSession(makeSession(id: "visible-task", status: .idle))
        NotificationCenter.default.post(
            name: BridgeServer.statusChangedNotification,
            object: nil,
            userInfo: [
                "sessionId": "visible-task",
                "status": SessionStatus.idle,
                "previousStatus": SessionStatus.executing,
            ]
        )
        #expect(soundPlayer.playedEvents.filter { $0 == .runningCompleted }.isEmpty)

        await manager.pollOnce()
        #expect(soundPlayer.playedEvents.filter { $0 == .runningCompleted }.count == 1)
    }

    @Test("respond allow triggers confirmationApproved")
    @MainActor
    func respondAllowTriggersApproved() async throws {
        let server = try makeMockBridgeServer()
        let soundPlayer = MockSoundPlayer()
        let manager = SessionManager(bridgeServer: server, settingsStore: makeSettings(), soundPlayer: soundPlayer)

        let session = makeSession()
        let conf = makeConfirmation()
        await server.injectSession(session)
        await server.injectConfirmation(conf, sessionId: session.id)

        try await manager.respond(session: session, confirmation: conf, response: .allow)

        #expect(soundPlayer.playedEvents.contains(.confirmationApproved))
    }

    @Test("respond deny triggers confirmationDenied")
    @MainActor
    func respondDenyTriggersDenied() async throws {
        let server = try makeMockBridgeServer()
        let soundPlayer = MockSoundPlayer()
        let manager = SessionManager(bridgeServer: server, settingsStore: makeSettings(), soundPlayer: soundPlayer)

        let session = makeSession()
        let conf = makeConfirmation()
        await server.injectSession(session)
        await server.injectConfirmation(conf, sessionId: session.id)

        try await manager.respond(session: session, confirmation: conf, response: .deny)

        #expect(soundPlayer.playedEvents.contains(.confirmationDenied))
    }

    @Test("respond select triggers confirmationApproved")
    @MainActor
    func respondSelectTriggersApproved() async throws {
        let server = try makeMockBridgeServer()
        let soundPlayer = MockSoundPlayer()
        let manager = SessionManager(bridgeServer: server, settingsStore: makeSettings(), soundPlayer: soundPlayer)

        let session = makeSession()
        let conf = makeConfirmation()
        await server.injectSession(session)
        await server.injectConfirmation(conf, sessionId: session.id)

        try await manager.respond(
            session: session, confirmation: conf,
            response: .select(optionId: "opt1")
        )

        #expect(soundPlayer.playedEvents.contains(.confirmationApproved))
    }

    @Test("pollOnce works without sound player")
    @MainActor
    func pollOnceWithoutSoundPlayer() async throws {
        let server = try makeMockBridgeServer()
        let manager = SessionManager(bridgeServer: server, settingsStore: makeSettings())
        await server.injectSession(makeSession())

        await manager.pollOnce()
        await manager.pollOnce()

        #expect(manager.sessions.count == 1)
    }

    @Test("respond multiSelect triggers confirmationApproved")
    @MainActor
    func respondMultiSelectTriggersApproved() async throws {
        let server = try makeMockBridgeServer()
        let soundPlayer = MockSoundPlayer()
        let manager = SessionManager(bridgeServer: server, settingsStore: makeSettings(), soundPlayer: soundPlayer)

        let session = makeSession()
        let conf = makeConfirmation()
        await server.injectSession(session)
        await server.injectConfirmation(conf, sessionId: session.id)

        try await manager.respond(
            session: session, confirmation: conf,
            response: .multiSelect(optionIds: ["opt1", "opt2"])
        )

        #expect(soundPlayer.playedEvents.contains(.confirmationApproved))
    }

    @Test("respond autoApprove triggers confirmationApproved")
    @MainActor
    func respondAutoApproveTriggersApproved() async throws {
        let server = try makeMockBridgeServer()
        let soundPlayer = MockSoundPlayer()
        let manager = SessionManager(bridgeServer: server, settingsStore: makeSettings(), soundPlayer: soundPlayer)

        let session = makeSession()
        let conf = makeConfirmation()
        await server.injectSession(session)
        await server.injectConfirmation(conf, sessionId: session.id)

        try await manager.respond(session: session, confirmation: conf, response: .autoApprove)

        #expect(soundPlayer.playedEvents.contains(.confirmationApproved))
    }

    @Test("respond freeText triggers confirmationApproved")
    @MainActor
    func respondFreeTextTriggersApproved() async throws {
        let server = try makeMockBridgeServer()
        let soundPlayer = MockSoundPlayer()
        let manager = SessionManager(bridgeServer: server, settingsStore: makeSettings(), soundPlayer: soundPlayer)

        let session = makeSession()
        let conf = makeConfirmation()
        await server.injectSession(session)
        await server.injectConfirmation(conf, sessionId: session.id)

        try await manager.respond(
            session: session, confirmation: conf,
            response: .freeText("Custom answer")
        )

        #expect(soundPlayer.playedEvents.contains(.confirmationApproved))
    }
}
