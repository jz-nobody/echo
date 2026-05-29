import Testing
import Foundation
@testable import AgentIsland

@Suite("BridgeServer Confirmation Tests")
struct BridgeServerConfirmationTests {

    private func makeBridgeServer() throws -> BridgeServer {
        try makeMockBridgeServer()
    }

    private func makePermissionMessage(
        sessionId: String = "s1", toolName: String = "Bash",
        toolInput: [String: AnyCodable]? = nil
    ) -> HookMessage {
        HookMessage(
            type: "PermissionRequest", sessionId: sessionId,
            toolName: toolName,
            toolInput: toolInput ?? ["command": AnyCodable("rm -rf /tmp/test")],
            permissionLevel: nil
        )
    }

    private func makeAskUserQuestionMessage(
        sessionId: String = "s1",
        question: String = "Which approach?",
        options: [[String: Any]] = [
            ["label": "Option A", "description": "First approach"],
            ["label": "Option B", "description": "Second approach"],
        ],
        multiSelect: Bool = false
    ) -> HookMessage {
        let questionsArray: [[String: Any]] = [[
            "question": question,
            "options": options,
            "multiSelect": multiSelect,
        ]]
        let input: [String: AnyCodable] = [
            "questions": AnyCodable(questionsArray)
        ]
        return HookMessage(
            type: "PermissionRequest", sessionId: sessionId,
            toolName: "AskUserQuestion", toolInput: input,
            permissionLevel: nil
        )
    }

    // MARK: - Permission Creation

    @Test("1. PermissionRequest creates PendingConfirmation")
    func permissionRequestCreatesConfirmation() async throws {
        let server = try makeBridgeServer()
        let clientID = UUID()
        let respond = { @Sendable (_: HookResponse) in }

        let msg = makePermissionMessage()
        await server.handlePermissionRequest(
            message: msg, sessionId: "claudeCode-s1", clientID: clientID, respond: respond
        )

        let confs = await server.pendingConfirmations
        #expect(confs.count == 1)
        let conf = confs.values.first!
        #expect(conf.type == .permission)
        #expect(conf.title.contains("Bash"))
    }

    @Test("2. respond(.allow) sends allow callback")
    func respondAllowSendsCallback() async throws {
        let server = try makeBridgeServer()
        let clientID = UUID()
        var capturedResponse: HookResponse?
        let respond: @Sendable (HookResponse) -> Void = { capturedResponse = $0 }

        let msg = makePermissionMessage()
        await server.handlePermissionRequest(
            message: msg, sessionId: "claudeCode-s1", clientID: clientID, respond: respond
        )

        let confs = await server.pendingConfirmations
        let confId = confs.keys.first!

        try await server.respond(confirmationId: confId, response: .allow)

        #expect(capturedResponse?.decision == "allow")
    }

    @Test("3. respond(.deny) sends deny callback")
    func respondDenySendsCallback() async throws {
        let server = try makeBridgeServer()
        let clientID = UUID()
        var capturedResponse: HookResponse?
        let respond: @Sendable (HookResponse) -> Void = { capturedResponse = $0 }

        let msg = makePermissionMessage()
        await server.handlePermissionRequest(
            message: msg, sessionId: "claudeCode-s1", clientID: clientID, respond: respond
        )

        let confs = await server.pendingConfirmations
        let confId = confs.keys.first!

        try await server.respond(confirmationId: confId, response: .deny)

        #expect(capturedResponse?.decision == "deny")
    }

    // MARK: - AskUserQuestion

    @Test("4. AskUserQuestion creates choice confirmation")
    func askUserQuestionCreatesChoice() async throws {
        let server = try makeBridgeServer()
        let clientID = UUID()
        let respond = { @Sendable (_: HookResponse) in }

        let msg = makeAskUserQuestionMessage()
        await server.handlePermissionRequest(
            message: msg, sessionId: "claudeCode-s1", clientID: clientID, respond: respond
        )

        let confs = await server.pendingConfirmations
        #expect(confs.count == 1)
        let conf = confs.values.first!
        #expect(conf.type == .choice)
        #expect(conf.title == "Which approach?")

        if case .choice(let details) = conf.details {
            #expect(details.options.count == 2)
            #expect(details.options[0].label == "Option A")
            #expect(details.multiSelect == false)
        } else {
            Issue.record("Expected choice details")
        }
    }

    @Test("5. respond(.select) sends updatedInput with answers")
    func respondSelectSendsUpdatedInput() async throws {
        let server = try makeBridgeServer()
        let clientID = UUID()
        var capturedResponse: HookResponse?
        let respond: @Sendable (HookResponse) -> Void = { capturedResponse = $0 }

        let msg = makeAskUserQuestionMessage()
        await server.handlePermissionRequest(
            message: msg, sessionId: "claudeCode-s1", clientID: clientID, respond: respond
        )

        let confs = await server.pendingConfirmations
        let confId = confs.keys.first!

        try await server.respond(confirmationId: confId, response: .select(optionId: "Option A"))

        #expect(capturedResponse?.decision == "allow")
        #expect(capturedResponse?.updatedInput != nil)
        if let answers = capturedResponse?.updatedInput?["answers"]?.value as? [String: Any] {
            #expect(answers["Which approach?"] as? String == "Option A")
        } else {
            Issue.record("Expected answers in updatedInput")
        }
    }

    @Test("6. respond(.multiSelect) sends multiple answers")
    func respondMultiSelectSendsAnswers() async throws {
        let server = try makeBridgeServer()
        let clientID = UUID()
        var capturedResponse: HookResponse?
        let respond: @Sendable (HookResponse) -> Void = { capturedResponse = $0 }

        let msg = makeAskUserQuestionMessage(multiSelect: true)
        await server.handlePermissionRequest(
            message: msg, sessionId: "claudeCode-s1", clientID: clientID, respond: respond
        )

        let confs = await server.pendingConfirmations
        let confId = confs.keys.first!

        try await server.respond(
            confirmationId: confId,
            response: .multiSelect(optionIds: ["Option A", "Option B"])
        )

        #expect(capturedResponse?.decision == "allow")
        if let answers = capturedResponse?.updatedInput?["answers"]?.value as? [String: Any] {
            #expect(answers["Which approach?"] as? String == "Option A, Option B")
        } else {
            Issue.record("Expected answers in updatedInput")
        }
    }

    @Test("7. respond(.freeText) sends text answer")
    func respondFreeTextSendsAnswer() async throws {
        let server = try makeBridgeServer()
        let clientID = UUID()
        var capturedResponse: HookResponse?
        let respond: @Sendable (HookResponse) -> Void = { capturedResponse = $0 }

        let msg = makeAskUserQuestionMessage()
        await server.handlePermissionRequest(
            message: msg, sessionId: "claudeCode-s1", clientID: clientID, respond: respond
        )

        let confs = await server.pendingConfirmations
        let confId = confs.keys.first!

        try await server.respond(
            confirmationId: confId, response: .freeText("Custom user response")
        )

        #expect(capturedResponse?.decision == "allow")
        if let answers = capturedResponse?.updatedInput?["answers"]?.value as? [String: Any] {
            #expect(answers["Which approach?"] as? String == "Custom user response")
        } else {
            Issue.record("Expected answers in updatedInput")
        }
    }

    // MARK: - Stale Interaction Cleanup

    @Test("8. clearStaleInteraction clears pending confirmation on new hook")
    func clearStaleOnNewHook() async throws {
        let server = try makeBridgeServer()
        let clientID = UUID()
        var staleResponse: HookResponse?
        let respond: @Sendable (HookResponse) -> Void = { staleResponse = $0 }

        let permMsg = makePermissionMessage()
        await server.handlePermissionRequest(
            message: permMsg, sessionId: "claudeCode-s1", clientID: clientID, respond: respond
        )

        let confs1 = await server.pendingConfirmations
        #expect(confs1.count == 1)

        let promptMsg = HookMessage(
            type: "UserPromptSubmit", sessionId: "test-session-1",
            toolName: nil, toolInput: nil, permissionLevel: nil
        )
        let respond2 = { @Sendable (_: HookResponse) in }
        await server.handleClaudeStatusHook(
            message: promptMsg, sessionId: "claudeCode-s1", respond: respond2
        )

        #expect(staleResponse?.decision == "ask")
        let confs2 = await server.pendingConfirmations
        #expect(confs2.isEmpty)
    }

    // MARK: - Client Disconnect

    @Test("9. Client disconnect cleans up confirmation")
    func clientDisconnectCleansUp() async throws {
        let server = try makeBridgeServer()
        let clientID = UUID()
        let respond = { @Sendable (_: HookResponse) in }

        let msg = makePermissionMessage()
        await server.handlePermissionRequest(
            message: msg, sessionId: "claudeCode-s1", clientID: clientID, respond: respond
        )

        let confs1 = await server.pendingConfirmations
        #expect(confs1.count == 1)

        await server.handleClientDisconnect(clientID: clientID)

        let confs2 = await server.pendingConfirmations
        #expect(confs2.isEmpty)
    }

    // MARK: - waitingConfirmation Status Protection

    @Test("10. waitingConfirmation status not overridden by PreToolUse")
    func waitingConfirmationBlocksStatusOverride() async throws {
        let server = try makeBridgeServer()
        let clientID = UUID()
        let respond = { @Sendable (_: HookResponse) in }

        let startMsg = HookMessage(
            type: "UserPromptSubmit", sessionId: "s1",
            toolName: nil, toolInput: nil, permissionLevel: nil
        )
        await server.handleClaudeStatusHook(
            message: startMsg, sessionId: "claudeCode-s1", respond: respond
        )

        let permMsg = makePermissionMessage()
        await server.handlePermissionRequest(
            message: permMsg, sessionId: "claudeCode-s1", clientID: clientID, respond: respond
        )

        let s1 = await server.sessions["claudeCode-s1"]
        #expect(s1?.status == .waitingConfirmation)

        let toolMsg = HookMessage(
            type: "PreToolUse", sessionId: "s1",
            toolName: "Read", toolInput: nil, permissionLevel: nil
        )
        await server.handleClaudeStatusHook(
            message: toolMsg, sessionId: "claudeCode-s1", respond: respond
        )

        let s2 = await server.sessions["claudeCode-s1"]
        #expect(s2?.status == .waitingConfirmation)
    }

    // MARK: - Stale Confirmation Timeout

    @Test("11. Stale confirmation cleaned after timeout")
    func staleConfirmationTimeout() async throws {
        let server = try makeBridgeServer()
        let clientID = UUID()
        var timeoutResponse: HookResponse?
        let respond: @Sendable (HookResponse) -> Void = { timeoutResponse = $0 }

        let msg = makePermissionMessage()
        await server.handlePermissionRequest(
            message: msg, sessionId: "claudeCode-s1", clientID: clientID, respond: respond
        )

        let confs = await server.pendingConfirmations
        let confId = confs.keys.first!
        await server.backdateConfirmation(confId, by: 86401)

        await server.cleanupStaleConfirmations()

        #expect(timeoutResponse?.decision == "ask")
        let confs2 = await server.pendingConfirmations
        #expect(confs2.isEmpty)
    }

    // MARK: - Cross-Session Safety

    @Test("12. Session restart doesn't affect other session's confirmations")
    func sessionRestartPreservesOtherSessionConfs() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let permMsg = makePermissionMessage(sessionId: "s-A")
        let clientA = UUID()
        await server.handlePermissionRequest(
            message: permMsg, sessionId: "claudeCode-s-A", clientID: clientA, respond: respond
        )

        let startMsg = HookMessage(
            type: "SessionStart", sessionId: "s-B",
            toolName: nil, toolInput: nil, permissionLevel: nil
        )
        await server.handleClaudeStatusHook(
            message: startMsg, sessionId: "claudeCode-s-B", respond: respond
        )

        let confs = await server.pendingConfirmations
        #expect(confs.count == 1)

        let confSession = await server.confirmationToSession
        #expect(confSession.values.first == "claudeCode-s-A")
    }

    // MARK: - Response Cleanup

    @Test("13. respond cleans up all associated state")
    func respondCleansUpAllState() async throws {
        let server = try makeBridgeServer()
        let clientID = UUID()
        let respond = { @Sendable (_: HookResponse) in }

        let msg = makePermissionMessage()
        await server.handlePermissionRequest(
            message: msg, sessionId: "claudeCode-s1", clientID: clientID, respond: respond
        )

        let confs = await server.pendingConfirmations
        let confId = confs.keys.first!

        try await server.respond(confirmationId: confId, response: .allow)

        let confs2 = await server.pendingConfirmations
        #expect(confs2.isEmpty)
        let callbacks = await server.responseCallbacks
        #expect(callbacks.isEmpty)
        let clientMap = await server.clientToConfirmation
        #expect(clientMap.isEmpty)
    }

    // MARK: - QoderWork Session Restart Safety (KEY FIX)

    @Test("14. QoderWork session restart does NOT destroy active confirmation")
    func qoderWorkSessionRestartDoesNotDestroyConf() async throws {
        let server = try makeBridgeServer()
        let clientID = UUID()
        var captured: HookResponse?
        let respond: @Sendable (HookResponse) -> Void = { captured = $0 }

        let startMsg = HookMessage(
            type: "UserPromptSubmit", sessionId: "qw1",
            toolName: nil, toolInput: nil, permissionLevel: nil,
            cwd: "/tmp/test"
        )
        let respond2 = { @Sendable (_: HookResponse) in }
        await server.handleQoderWorkStatusHook(
            message: startMsg, sessionId: "qoderWork-qw1", clientPID: nil, respond: respond2
        )

        let permMsg = HookMessage(
            type: "PermissionRequest", sessionId: "qw1",
            toolName: "Bash",
            toolInput: ["command": AnyCodable("make build")],
            permissionLevel: nil
        )
        await server.handlePermissionRequest(
            message: permMsg, sessionId: "qoderWork-qw1", clientID: clientID, respond: respond
        )

        let confs1 = await server.pendingConfirmations
        #expect(confs1.count == 1)

        let restartMsg = HookMessage(
            type: "SessionStart", sessionId: "qw1",
            toolName: nil, toolInput: nil, permissionLevel: nil,
            cwd: "/tmp/test"
        )
        await server.handleQoderWorkStatusHook(
            message: restartMsg, sessionId: "qoderWork-qw1", clientPID: nil, respond: respond2
        )

        let confs2 = await server.pendingConfirmations
        #expect(confs2.count == 1)

        #expect(captured == nil)

        let confId = confs2.keys.first!
        try await server.respond(confirmationId: confId, response: .allow)
        #expect(captured?.decision == "allow")
    }

    // MARK: - Always Allow

    @Test("Always Allow sends updatedPermissions in response")
    func respondAllowAlwaysSendsUpdatedPermissions() async throws {
        let server = try makeBridgeServer()
        let clientID = UUID()
        var capturedResponse: HookResponse?
        let respond: @Sendable (HookResponse) -> Void = { capturedResponse = $0 }

        let msg = makePermissionMessage(toolName: "Bash")
        await server.handlePermissionRequest(
            message: msg, sessionId: "claudeCode-s1", clientID: clientID, respond: respond
        )

        let confs = await server.pendingConfirmations
        let confId = confs.keys.first!

        try await server.respond(confirmationId: confId, response: .allowAlways(toolName: "Bash"))

        #expect(capturedResponse?.decision == "allow")
        #expect(capturedResponse?.updatedPermissions != nil)

        let perms = capturedResponse!.updatedPermissions!
        #expect(perms.count == 1)
        #expect(perms[0]["type"]?.value as? String == "addRules")
        #expect(perms[0]["destination"]?.value as? String == "session")
        #expect(perms[0]["behavior"]?.value as? String == "allow")
    }

    @Test("Always Allow transitions to executing like regular allow")
    func allowAlwaysTransitionsToExecuting() async throws {
        let server = try makeBridgeServer()
        let clientID = UUID()
        let respond = { @Sendable (_: HookResponse) in }

        let startMsg = HookMessage(
            type: "UserPromptSubmit", sessionId: "s1",
            toolName: nil, toolInput: nil, permissionLevel: nil
        )
        await server.handleClaudeStatusHook(
            message: startMsg, sessionId: "claudeCode-s1", respond: respond
        )

        let permMsg = makePermissionMessage()
        await server.handlePermissionRequest(
            message: permMsg, sessionId: "claudeCode-s1", clientID: clientID, respond: respond
        )
        let s1 = await server.sessions["claudeCode-s1"]
        #expect(s1?.status == .waitingConfirmation)

        let confs = await server.pendingConfirmations
        let confId = confs.keys.first!
        try await server.respond(confirmationId: confId, response: .allowAlways(toolName: "Bash"))

        let s2 = await server.sessions["claudeCode-s1"]
        #expect(s2?.status == .executing)
    }

    // MARK: - Auto Approve

    @Test("Auto approve short-circuits new PermissionRequests")
    func autoApproveShortCircuits() async throws {
        let server = try makeBridgeServer()
        let respond1 = { @Sendable (_: HookResponse) in }

        let startMsg = HookMessage(
            type: "UserPromptSubmit", sessionId: "s1",
            toolName: nil, toolInput: nil, permissionLevel: nil
        )
        await server.handleClaudeStatusHook(
            message: startMsg, sessionId: "claudeCode-s1", respond: respond1
        )

        await server.enableAutoApprove(sessionId: "claudeCode-s1")

        var capturedResponse: HookResponse?
        let respond2: @Sendable (HookResponse) -> Void = { capturedResponse = $0 }

        let msg = makePermissionMessage()
        await server.handlePermissionRequest(
            message: msg, sessionId: "claudeCode-s1", clientID: UUID(), respond: respond2
        )

        #expect(capturedResponse?.decision == "allow")
        let confs = await server.pendingConfirmations
        #expect(confs.isEmpty)
    }

    @Test("Auto approve drains queued permission confirmations")
    func autoApproveDrainsQueue() async throws {
        let server = try makeBridgeServer()
        var responses: [HookResponse] = []
        let respond: @Sendable (HookResponse) -> Void = { responses.append($0) }

        let msg1 = makePermissionMessage(sessionId: "s1", toolName: "Bash")
        await server.handlePermissionRequest(
            message: msg1, sessionId: "claudeCode-s1", clientID: UUID(), respond: respond
        )
        let msg2 = makePermissionMessage(sessionId: "s1", toolName: "Edit")
        await server.handlePermissionRequest(
            message: msg2, sessionId: "claudeCode-s1", clientID: UUID(), respond: respond
        )

        let confsBefore = await server.pendingConfirmations
        #expect(confsBefore.count == 2)

        await server.enableAutoApprove(sessionId: "claudeCode-s1")

        let confsAfter = await server.pendingConfirmations
        #expect(confsAfter.isEmpty)
        #expect(responses.count == 2)
        #expect(responses.allSatisfy { $0.decision == "allow" })
    }

    @Test("Auto approve does not drain AskUserQuestion confirmations")
    func autoApproveSkipsChoiceConfirmations() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let permMsg = makePermissionMessage(sessionId: "s1", toolName: "Bash")
        await server.handlePermissionRequest(
            message: permMsg, sessionId: "claudeCode-s1", clientID: UUID(), respond: respond
        )

        let choiceMsg = makeAskUserQuestionMessage(sessionId: "s1")
        await server.handlePermissionRequest(
            message: choiceMsg, sessionId: "claudeCode-s1", clientID: UUID(), respond: respond
        )

        let confsBefore = await server.pendingConfirmations
        #expect(confsBefore.count == 2)

        await server.enableAutoApprove(sessionId: "claudeCode-s1")

        let confsAfter = await server.pendingConfirmations
        #expect(confsAfter.count == 1)
        let remaining = confsAfter.values.first!
        #expect(remaining.type == .choice)
    }

    @Test("Revoke auto approve clears local flag")
    func revokeAutoApproveClearsLocal() async throws {
        let server = try makeBridgeServer()
        await server.enableAutoApprove(sessionId: "claudeCode-s1")

        let flagBefore = await server.localAutoApprove.contains("claudeCode-s1")
        #expect(flagBefore)

        await server.revokeAutoApprove(sessionId: "claudeCode-s1")

        let flagAfter = await server.localAutoApprove.contains("claudeCode-s1")
        #expect(!flagAfter)
    }

    @Test("After revoke, new PermissionRequests queue normally")
    func afterRevokeRequestsQueueAgain() async throws {
        let server = try makeBridgeServer()
        await server.enableAutoApprove(sessionId: "claudeCode-s1")
        await server.revokeAutoApprove(sessionId: "claudeCode-s1")

        let respond = { @Sendable (_: HookResponse) in }
        let msg = makePermissionMessage()
        await server.handlePermissionRequest(
            message: msg, sessionId: "claudeCode-s1", clientID: UUID(), respond: respond
        )

        let confs = await server.pendingConfirmations
        #expect(confs.count == 1)
    }

    @Test("Auto approve does not short-circuit AskUserQuestion")
    func autoApproveDoesNotShortCircuitChoice() async throws {
        let server = try makeBridgeServer()
        await server.enableAutoApprove(sessionId: "claudeCode-s1")

        let respond = { @Sendable (_: HookResponse) in }
        let msg = makeAskUserQuestionMessage(sessionId: "s1")
        await server.handlePermissionRequest(
            message: msg, sessionId: "claudeCode-s1", clientID: UUID(), respond: respond
        )

        let confs = await server.pendingConfirmations
        #expect(confs.count == 1)
        let conf = confs.values.first!
        #expect(conf.type == .choice)
    }

    @Test("enableAutoApprove sets permissionMode on session")
    func enableAutoApproveSetsPermissionMode() async throws {
        let server = try makeBridgeServer()
        await server.ensureSessionExists(id: "claudeCode-s1", agentType: .claudeCode, title: "Test")

        await server.enableAutoApprove(sessionId: "claudeCode-s1")

        let session = await server.sessions["claudeCode-s1"]
        #expect(session?.permissionMode == "autoApprove")
    }

    // MARK: - Respond to Nonexistent Confirmation

    @Test("15. Responding to unknown confirmation throws")
    func respondToUnknownThrows() async throws {
        let server = try makeBridgeServer()

        await #expect(throws: BridgeServer.BridgeServerError.self) {
            try await server.respond(confirmationId: "nonexistent-id", response: .allow)
        }
    }

    // MARK: - Diff Building

    @Test("16. buildDiff generates diff lines from Edit input")
    func buildDiffFromEditInput() async throws {
        let server = try makeBridgeServer()
        let input: [String: AnyCodable] = [
            "old_string": AnyCodable("let x = 1"),
            "new_string": AnyCodable("let x = 2"),
        ]
        let diff = await server.buildDiff(from: input)
        #expect(diff.count == 2)
        #expect(diff[0].type == .removed)
        #expect(diff[0].content == "let x = 1")
        #expect(diff[1].type == .added)
        #expect(diff[1].content == "let x = 2")
    }

    @Test("17. buildDiff generates add-only lines from Write input")
    func buildDiffFromWriteInput() async throws {
        let server = try makeBridgeServer()
        let input: [String: AnyCodable] = [
            "content": AnyCodable("line 1\nline 2\nline 3")
        ]
        let diff = await server.buildDiff(from: input)
        #expect(diff.count == 3)
        #expect(diff.allSatisfy { $0.type == .added })
    }

    // MARK: - Multiple Confirmations Per Session

    @Test("18. Multiple confirmations for same session tracked independently")
    func multipleConfirmationsPerSession() async throws {
        let server = try makeBridgeServer()
        let client1 = UUID()
        let client2 = UUID()
        let respond = { @Sendable (_: HookResponse) in }

        let msg1 = makePermissionMessage(sessionId: "s1", toolName: "Bash")
        await server.handlePermissionRequest(
            message: msg1, sessionId: "claudeCode-s1", clientID: client1, respond: respond
        )

        let msg2 = makePermissionMessage(sessionId: "s1", toolName: "Edit")
        await server.handlePermissionRequest(
            message: msg2, sessionId: "claudeCode-s1", clientID: client2, respond: respond
        )

        let confs = await server.pendingConfirmations
        #expect(confs.count == 2)
    }

    // MARK: - hasConfirmationsFor

    @Test("19. hasConfirmationsFor returns correct state")
    func hasConfirmationsForCheck() async throws {
        let server = try makeBridgeServer()
        let clientID = UUID()
        let respond = { @Sendable (_: HookResponse) in }

        let before = await server.hasConfirmationsFor(sessionId: "claudeCode-s1")
        #expect(before == false)

        let msg = makePermissionMessage()
        await server.handlePermissionRequest(
            message: msg, sessionId: "claudeCode-s1", clientID: clientID, respond: respond
        )

        let after = await server.hasConfirmationsFor(sessionId: "claudeCode-s1")
        #expect(after == true)
    }

    // MARK: - Permission Approved/Denied Events

    @Test("20. Allow transitions from waitingConfirmation to executing")
    func allowTransitionsToExecuting() async throws {
        let server = try makeBridgeServer()
        let clientID = UUID()
        let respond = { @Sendable (_: HookResponse) in }

        let startMsg = HookMessage(
            type: "UserPromptSubmit", sessionId: "s1",
            toolName: nil, toolInput: nil, permissionLevel: nil
        )
        await server.handleClaudeStatusHook(
            message: startMsg, sessionId: "claudeCode-s1", respond: respond
        )

        let permMsg = makePermissionMessage()
        await server.handlePermissionRequest(
            message: permMsg, sessionId: "claudeCode-s1", clientID: clientID, respond: respond
        )
        let s1 = await server.sessions["claudeCode-s1"]
        #expect(s1?.status == .waitingConfirmation)

        let confs = await server.pendingConfirmations
        let confId = confs.keys.first!
        try await server.respond(confirmationId: confId, response: .allow)

        let s2 = await server.sessions["claudeCode-s1"]
        #expect(s2?.status == .executing)
    }

    @Test("21. Deny transitions from waitingConfirmation to idle")
    func denyTransitionsToIdle() async throws {
        let server = try makeBridgeServer()
        let clientID = UUID()
        let respond = { @Sendable (_: HookResponse) in }

        let startMsg = HookMessage(
            type: "UserPromptSubmit", sessionId: "s1",
            toolName: nil, toolInput: nil, permissionLevel: nil
        )
        await server.handleClaudeStatusHook(
            message: startMsg, sessionId: "claudeCode-s1", respond: respond
        )

        let permMsg = makePermissionMessage()
        await server.handlePermissionRequest(
            message: permMsg, sessionId: "claudeCode-s1", clientID: clientID, respond: respond
        )

        let confs = await server.pendingConfirmations
        let confId = confs.keys.first!
        try await server.respond(confirmationId: confId, response: .deny)

        let s2 = await server.sessions["claudeCode-s1"]
        #expect(s2?.status == .idle)
    }

    // MARK: - removeSession Sends Ask (Not Empty)

    @Test("22. removeSession sends ask decision to active callbacks")
    func removeSessionSendsAsk() async throws {
        let server = try makeBridgeServer()
        let clientID = UUID()
        var capturedResponse: HookResponse?
        let respond: @Sendable (HookResponse) -> Void = { capturedResponse = $0 }

        let msg = makePermissionMessage()
        await server.handlePermissionRequest(
            message: msg, sessionId: "claudeCode-s1", clientID: clientID, respond: respond
        )

        await server.removeSession("claudeCode-s1")

        #expect(capturedResponse?.decision == "ask")
        #expect(capturedResponse?.reason == "Session ended")
    }
}

extension BridgeServer {
    func backdateConfirmation(_ confId: String, by seconds: TimeInterval) {
        guard var conf = pendingConfirmations[confId] else { return }
        let oldDate = conf.timestamp.addingTimeInterval(-seconds)
        pendingConfirmations[confId] = PendingConfirmation(
            id: conf.id, type: conf.type, title: conf.title,
            details: conf.details, timestamp: oldDate
        )
    }
}
