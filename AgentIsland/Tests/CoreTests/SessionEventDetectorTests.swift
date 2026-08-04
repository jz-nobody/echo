import Testing
import Foundation
@testable import AgentIsland

@Suite("SessionEventDetector Tests")
struct SessionEventDetectorTests {

    private func makeSession(
        id: String = "s1",
        status: SessionStatus = .executing,
        agentType: AgentType = .qoderWork,
        subagents: [SubagentInfo]? = nil
    ) -> AgentSession {
        var session = AgentSession(
            id: id,
            agentType: agentType,
            title: "Task",
            status: status,
            startTime: Date(),
            lastUpdate: Date(),
            terminalInfo: nil,
            currentToolCall: nil
        )
        session.subagents = subagents
        return session
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

    @Test("first poll emits no events")
    @MainActor
    func firstPollNoEvents() {
        let detector = SessionEventDetector()
        let events = detector.detect(
            sessions: [makeSession()],
            confirmations: [:],
            health: AdaptorHealth()
        )
        #expect(events.isEmpty)
    }

    @Test("new active session emits sessionStart")
    @MainActor
    func newSessionEmitsStart() {
        let detector = SessionEventDetector()
        let health = AdaptorHealth()

        _ = detector.detect(sessions: [], confirmations: [:], health: health)

        let events = detector.detect(
            sessions: [makeSession(id: "s1", status: .executing)],
            confirmations: [:],
            health: health
        )
        #expect(events.contains(.sessionStart))
    }

    @Test("idle session does not emit sessionStart")
    @MainActor
    func idleSessionNoStart() {
        let detector = SessionEventDetector()
        let health = AdaptorHealth()

        _ = detector.detect(sessions: [], confirmations: [:], health: health)

        let events = detector.detect(
            sessions: [makeSession(id: "s1", status: .idle)],
            confirmations: [:],
            health: health
        )
        #expect(!events.contains(.sessionStart))
    }

    @Test("session disappeared emits sessionEnd")
    @MainActor
    func sessionDisappearedEmitsEnd() {
        let detector = SessionEventDetector()
        let health = AdaptorHealth()

        _ = detector.detect(
            sessions: [makeSession(id: "s1", status: .executing)],
            confirmations: [:],
            health: health
        )

        let events = detector.detect(
            sessions: [],
            confirmations: [:],
            health: health
        )
        #expect(events.contains(.sessionEnd))
    }

    @Test("temporarily hidden Codex session does not emit sessionEnd")
    @MainActor
    func hiddenCodexSessionDoesNotEmitEnd() {
        let detector = SessionEventDetector()
        let health = AdaptorHealth()

        _ = detector.detect(
            sessions: [makeSession(id: "codex-child", agentType: .codex)],
            confirmations: [:],
            health: health
        )

        let events = detector.detect(sessions: [], confirmations: [:], health: health)
        #expect(!events.contains(.sessionEnd))
    }

    @Test("Codex parent becoming idle while a subagent is active does not sound complete")
    @MainActor
    func codexParentWithSubagentDoesNotSoundComplete() {
        let detector = SessionEventDetector()
        let health = AdaptorHealth()
        let activeSubagent = SubagentInfo(
            id: "codex-child", description: "Worker",
            agentType: "codex", isComplete: false
        )

        _ = detector.detect(
            sessions: [makeSession(
                id: "codex-parent", status: .executing,
                agentType: .codex, subagents: [activeSubagent]
            )],
            confirmations: [:],
            health: health
        )

        let events = detector.detect(
            sessions: [makeSession(
                id: "codex-parent", status: .idle,
                agentType: .codex, subagents: [activeSubagent]
            )],
            confirmations: [:],
            health: health
        )
        #expect(!events.contains(.runningCompleted))
        #expect(!events.contains(.sessionEnd))
    }

    @Test("session completed emits sessionEnd")
    @MainActor
    func sessionCompletedEmitsEnd() {
        let detector = SessionEventDetector()
        let health = AdaptorHealth()

        _ = detector.detect(
            sessions: [makeSession(id: "s1", status: .executing)],
            confirmations: [:],
            health: health
        )

        let events = detector.detect(
            sessions: [makeSession(id: "s1", status: .completed)],
            confirmations: [:],
            health: health
        )
        #expect(events.contains(.sessionEnd))
        #expect(!events.contains(.runningCompleted))
    }

    @Test("new confirmation emits confirmationArrived")
    @MainActor
    func newConfirmationEmitsArrived() {
        let detector = SessionEventDetector()
        let health = AdaptorHealth()
        let session = makeSession(id: "s1", status: .waitingConfirmation)

        _ = detector.detect(sessions: [session], confirmations: [:], health: health)

        let events = detector.detect(
            sessions: [session],
            confirmations: ["s1": [makeConfirmation(id: "c1")]],
            health: health
        )
        #expect(events.contains(.confirmationArrived))
    }

    @Test("status changed to error emits error")
    @MainActor
    func statusChangedToErrorEmitsError() {
        let detector = SessionEventDetector()
        let health = AdaptorHealth()

        _ = detector.detect(
            sessions: [makeSession(id: "s1", status: .thinking)],
            confirmations: [:],
            health: health
        )

        let events = detector.detect(
            sessions: [makeSession(id: "s1", status: .error("timeout"))],
            confirmations: [:],
            health: health
        )
        #expect(events.contains(.error))
    }

    @Test("status already error does not re-emit")
    @MainActor
    func alreadyErrorNoReEmit() {
        let detector = SessionEventDetector()
        let health = AdaptorHealth()

        _ = detector.detect(
            sessions: [makeSession(id: "s1", status: .error("timeout"))],
            confirmations: [:],
            health: health
        )

        let events = detector.detect(
            sessions: [makeSession(id: "s1", status: .error("timeout"))],
            confirmations: [:],
            health: health
        )
        #expect(!events.contains(.error))
    }

    @Test("adaptor reconnected emits reconnected")
    @MainActor
    func adaptorReconnectedEmitsReconnected() {
        let detector = SessionEventDetector()
        let health = AdaptorHealth()

        health.recordFailure(for: .qoderWork)
        health.recordFailure(for: .qoderWork)
        health.recordFailure(for: .qoderWork)
        _ = detector.detect(sessions: [], confirmations: [:], health: health)

        health.recordSuccess(for: .qoderWork)
        let events = detector.detect(sessions: [], confirmations: [:], health: health)
        #expect(events.contains(.reconnected))
    }

    @Test("multiple events in one poll")
    @MainActor
    func multipleEventsInOnePoll() {
        let detector = SessionEventDetector()
        let health = AdaptorHealth()

        _ = detector.detect(
            sessions: [makeSession(id: "s1", status: .executing)],
            confirmations: [:],
            health: health
        )

        let events = detector.detect(
            sessions: [
                makeSession(id: "s2", status: .thinking),
                makeSession(id: "s3", status: .error("fail"))
            ],
            confirmations: ["s2": [makeConfirmation(id: "c1")]],
            health: health
        )
        #expect(events.contains(.sessionStart))
        #expect(events.contains(.sessionEnd))
        #expect(events.contains(.confirmationArrived))
        #expect(events.contains(.error))
    }
}
