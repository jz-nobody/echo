import Testing
import Foundation
@testable import AgentIsland

@Suite("SessionState Tests")
struct SessionStateTests {

    @Test("1. Session starts with idle status")
    func sessionStartsIdle() {
        var state = SessionState()
        state.apply(.sessionStart)
        #expect(state.status == .idle)
    }

    @Test("2. UserPromptSubmit transitions to executing")
    func userPromptSubmitToExecuting() {
        var state = SessionState(status: .idle)
        state.apply(.userPromptSubmit)
        #expect(state.status == .executing)
    }

    @Test("3. PreToolUse(Read) transitions to reading")
    func preToolUseReadToReading() {
        var state = SessionState(status: .executing)
        state.apply(.preToolUse(toolName: "Read"))
        #expect(state.status == .reading)
    }

    @Test("4. PreToolUse(Edit) transitions to editing")
    func preToolUseEditToEditing() {
        var state = SessionState(status: .executing)
        state.apply(.preToolUse(toolName: "Edit"))
        #expect(state.status == .editing)
    }

    @Test("5. PreToolUse(Bash) transitions to executing")
    func preToolUseBashToExecuting() {
        var state = SessionState(status: .reading)
        state.apply(.preToolUse(toolName: "Bash"))
        #expect(state.status == .executing)
    }

    @Test("6. PostToolUse stays executing (not idle)")
    func postToolUseStaysExecuting() {
        var state = SessionState(status: .reading)
        state.apply(.postToolUse)
        #expect(state.status == .executing)
    }

    @Test("7. PermissionRequest transitions to waitingConfirmation")
    func permissionRequestToWaiting() {
        var state = SessionState(status: .executing)
        state.apply(.permissionRequest)
        #expect(state.status == .waitingConfirmation)
    }

    @Test("8. While waitingConfirmation, PreToolUse is IGNORED")
    func waitingProtectedFromPreToolUse() {
        var state = SessionState(status: .waitingConfirmation)
        state.apply(.preToolUse(toolName: "Bash"))
        #expect(state.status == .waitingConfirmation)
    }

    @Test("9. PermissionApproved transitions to executing")
    func approvalToExecuting() {
        var state = SessionState(status: .waitingConfirmation)
        state.apply(.permissionApproved)
        #expect(state.status == .executing)
    }

    @Test("10. PermissionDenied transitions to idle")
    func denialToIdle() {
        var state = SessionState(status: .waitingConfirmation)
        state.apply(.permissionDenied)
        #expect(state.status == .idle)
    }

    @Test("11. Stop transitions to idle")
    func stopToIdle() {
        var state = SessionState(status: .executing)
        state.apply(.stop)
        #expect(state.status == .idle)
    }

    @Test("12. PreCompact transitions to compacting")
    func preCompactToCompacting() {
        var state = SessionState(status: .executing)
        state.apply(.preCompact)
        #expect(state.status == .compacting)
        #expect(state.isCompacting == true)
    }

    @Test("13. After PreCompact, activity event ends compacting")
    func activityAfterCompactEndsCompacting() {
        var state = SessionState(status: .executing)
        state.apply(.preCompact)
        #expect(state.status == .compacting)
        state.apply(.preToolUse(toolName: "Read"))
        #expect(state.status == .reading)
        #expect(state.isCompacting == false)
    }

    @Test("14. No TTL: status persists without new events")
    func noFallbackToIdleWithoutEvent() {
        var state = SessionState(status: .executing)
        state.apply(.preToolUse(toolName: "Bash"))
        #expect(state.status == .executing)
    }

    @Test("15. StopFailure transitions to idle")
    func stopFailureToIdle() {
        var state = SessionState(status: .executing)
        state.apply(.stopFailure)
        #expect(state.status == .idle)
    }

    @Test("waitingConfirmation protected from userPromptSubmit")
    func waitingProtectedFromUserPrompt() {
        var state = SessionState(status: .waitingConfirmation)
        state.apply(.userPromptSubmit)
        #expect(state.status == .waitingConfirmation)
    }

    @Test("waitingConfirmation protected from postToolUse")
    func waitingProtectedFromPostToolUse() {
        var state = SessionState(status: .waitingConfirmation)
        state.apply(.postToolUse)
        #expect(state.status == .waitingConfirmation)
    }

    @Test("waitingConfirmation protected from preCompact")
    func waitingProtectedFromPreCompact() {
        var state = SessionState(status: .waitingConfirmation)
        state.apply(.preCompact)
        #expect(state.status == .waitingConfirmation)
    }

    @Test("waitingConfirmation NOT protected from stop")
    func stopOverridesWaiting() {
        var state = SessionState(status: .waitingConfirmation)
        state.apply(.stop)
        #expect(state.status == .idle)
    }

    @Test("subagentStart transitions to executing when not actionable")
    func subagentStartToExecuting() {
        var state = SessionState(status: .idle)
        state.apply(.subagentStart)
        #expect(state.status == .executing)
    }

    @Test("subagentStop does not change status")
    func subagentStopNoChange() {
        var state = SessionState(status: .executing)
        state.apply(.subagentStop)
        #expect(state.status == .executing)
    }

    @Test("processTerminated transitions to idle")
    func processTerminatedToIdle() {
        var state = SessionState(status: .executing)
        state.apply(.processTerminated)
        #expect(state.status == .idle)
    }

    @Test("postToolUse after compacting ends compacting")
    func postToolUseEndsCompacting() {
        var state = SessionState(status: .executing)
        state.apply(.preCompact)
        #expect(state.isCompacting == true)
        state.apply(.postToolUse)
        #expect(state.status == .executing)
        #expect(state.isCompacting == false)
    }

    @Test("refineExecuting maps WebSearch to reading")
    func refineWebSearch() {
        #expect(SessionState.refineExecuting(toolName: "WebSearch") == .reading)
    }

    @Test("refineExecuting maps Write to editing")
    func refineWrite() {
        #expect(SessionState.refineExecuting(toolName: "Write") == .editing)
    }

    @Test("refineExecuting maps nil to executing")
    func refineNil() {
        #expect(SessionState.refineExecuting(toolName: nil) == .executing)
    }

    @Test("refineExecuting maps Agent to executing")
    func refineAgent() {
        #expect(SessionState.refineExecuting(toolName: "Agent") == .executing)
    }
}
