import Testing
import Foundation
@testable import AgentIsland

@Suite("QoderWorkAdaptor Tests", .serialized)
struct QoderWorkAdaptorTests {

    private func makeAdaptor(handler: @escaping (String, [String: Any]?) throws -> MCPToolResult) async -> QoderWorkAdaptor {
        let mock = MockMCPClient()
        await mock.setHandler(handler)
        return QoderWorkAdaptor(client: mock)
    }

    private func textResult(_ json: String) -> MCPToolResult {
        MCPToolResult(content: [MCPContent(type: "text", text: json)])
    }

    // MARK: - discoverSessions

    @Test("discoverSessions parses task list")
    func discoverSessionsParsesTaskList() async throws {
        let adaptor = await makeAdaptor { name, _ in
            #expect(name == "qoder_list_tasks")
            return self.textResult("""
                {"tasks":[{"id":"task-1","title":"Fix bug","status":"running","toolCalls":[{"state":"input-streaming","name":"edit_file"}]}]}
                """)
        }

        let sessions = try await adaptor.discoverSessions()
        #expect(sessions.count == 1)
        #expect(sessions[0].id == "task-1")
        #expect(sessions[0].title == "Fix bug")
        #expect(sessions[0].status == .thinking)
        #expect(sessions[0].agentType == .qoderWork)
        #expect(sessions[0].currentToolCall == "edit_file")
    }

    @Test("discoverSessions returns empty for no tasks")
    func discoverSessionsEmptyList() async throws {
        let adaptor = await makeAdaptor { _, _ in
            self.textResult("""
                {"tasks":[]}
                """)
        }

        let sessions = try await adaptor.discoverSessions()
        #expect(sessions.isEmpty)
    }

    // MARK: - getStatus

    @Test("getStatus maps running + input-streaming to thinking")
    func getStatusRunningInputStreaming() async throws {
        let adaptor = await makeAdaptor { _, _ in
            self.textResult("""
                {"status":"running","toolCalls":[{"state":"input-streaming","name":"write"}]}
                """)
        }

        let session = makeSession(id: "t1")
        let status = try await adaptor.getStatus(session: session)
        #expect(status == .thinking)
    }

    @Test("getStatus maps running + call to waitingConfirmation")
    func getStatusRunningCall() async throws {
        let adaptor = await makeAdaptor { _, _ in
            self.textResult("""
                {"status":"running","toolCalls":[{"state":"call","name":"execute_command"}]}
                """)
        }

        let session = makeSession(id: "t1")
        let status = try await adaptor.getStatus(session: session)
        #expect(status == .waitingConfirmation)
    }

    @Test("getStatus maps completed")
    func getStatusCompleted() async throws {
        let adaptor = await makeAdaptor { _, _ in
            self.textResult("""
                {"status":"completed","toolCalls":[]}
                """)
        }

        let session = makeSession(id: "t1")
        let status = try await adaptor.getStatus(session: session)
        #expect(status == .completed)
    }

    // MARK: - getPendingConfirmations

    @Test("getPendingConfirmations parses permission tool call")
    func getPendingConfirmationsPermission() async throws {
        let adaptor = await makeAdaptor { _, _ in
            self.textResult("""
                {"status":"running","toolCalls":[{"id":"call-1","state":"call","name":"edit_file","input":{"operation":"Edit src/main.swift"}}]}
                """)
        }

        let session = makeSession(id: "t1")
        let confirmations = try await adaptor.getPendingConfirmations(session: session)
        #expect(confirmations.count == 1)
        #expect(confirmations[0].id == "call-1")
        #expect(confirmations[0].type == .permission)
        #expect(confirmations[0].title == "Edit src/main.swift")
    }

    @Test("getPendingConfirmations parses choice tool call")
    func getPendingConfirmationsChoice() async throws {
        let adaptor = await makeAdaptor { _, _ in
            self.textResult("""
                {"status":"running","toolCalls":[{"id":"call-2","state":"call","name":"ask_user","input":{"question":"Which framework?","options":[{"id":"a","label":"SwiftUI","description":"Modern"},{"id":"b","label":"AppKit","description":"Classic"}]}}]}
                """)
        }

        let session = makeSession(id: "t1")
        let confirmations = try await adaptor.getPendingConfirmations(session: session)
        #expect(confirmations.count == 1)
        #expect(confirmations[0].type == .choice)
        if case .choice(let details) = confirmations[0].details {
            #expect(details.question == "Which framework?")
            #expect(details.options.count == 2)
            #expect(details.options[0].id == "a")
            #expect(details.options[0].label == "SwiftUI")
        } else {
            Issue.record("Expected choice details")
        }
    }

    // MARK: - respond

    @Test("respond allow sends approve")
    func respondAllowSendsApprove() async throws {
        var capturedArgs: [String: Any]?
        let adaptor = await makeAdaptor { name, args in
            #expect(name == "qoder_respond_task")
            capturedArgs = args
            return self.textResult("{}")
        }

        let session = makeSession(id: "task-99")
        let confirmation = makeConfirmation(id: "c1")
        try await adaptor.respond(session: session, confirmation: confirmation, response: .allow)

        #expect(capturedArgs?["taskId"] as? String == "task-99")
        #expect(capturedArgs?["response"] as? String == "approve")
    }

    @Test("respond deny sends deny")
    func respondDenySendsDeny() async throws {
        var capturedArgs: [String: Any]?
        let adaptor = await makeAdaptor { _, args in
            capturedArgs = args
            return self.textResult("{}")
        }

        let session = makeSession(id: "task-99")
        let confirmation = makeConfirmation(id: "c1")
        try await adaptor.respond(session: session, confirmation: confirmation, response: .deny)

        #expect(capturedArgs?["response"] as? String == "deny")
    }

    @Test("respond select sends answer with optionId")
    func respondSelectSendsAnswer() async throws {
        var capturedArgs: [String: Any]?
        let adaptor = await makeAdaptor { _, args in
            capturedArgs = args
            return self.textResult("{}")
        }

        let session = makeSession(id: "task-99")
        let confirmation = makeConfirmation(id: "c1")
        try await adaptor.respond(session: session, confirmation: confirmation, response: .select(optionId: "opt-a"))

        #expect(capturedArgs?["response"] as? String == "answer")
        #expect(capturedArgs?["answer"] as? String == "opt-a")
    }

    // MARK: - isAvailable

    @Test("isAvailable delegates to client")
    func isAvailableDelegatesToClient() async {
        let mock = MockMCPClient()
        await mock.setReachable(false)
        let adaptor = QoderWorkAdaptor(client: mock)

        let available = await adaptor.isAvailable
        #expect(available == false)
    }

    // MARK: - Helpers

    private func makeSession(id: String) -> AgentSession {
        AgentSession(
            id: id,
            agentType: .qoderWork,
            title: "Test",
            status: .idle,
            startTime: Date(),
            lastUpdate: Date(),
            terminalInfo: nil,
            currentToolCall: nil
        )
    }

    private func makeConfirmation(id: String) -> PendingConfirmation {
        PendingConfirmation(
            id: id,
            type: .permission,
            title: "Test",
            details: .permission(PermissionDetails(operation: "test", diff: [], additions: 0, deletions: 0)),
            timestamp: Date()
        )
    }
}
