import Testing
@testable import AgentIsland

@Suite("SessionStatus Tests")
struct SessionStatusTests {

    @Test("each status has correct display text")
    func displayText() {
        #expect(SessionStatus.idle.displayText == "空闲中")
        #expect(SessionStatus.thinking.displayText == "思考中")
        #expect(SessionStatus.executing.displayText == "执行中")
        #expect(SessionStatus.completed.displayText == "已完成")
        #expect(SessionStatus.waitingConfirmation.displayText == "等待确认")
        #expect(SessionStatus.error("timeout").displayText == "错误")
    }

    @Test("priority ordering is correct")
    func priorityOrdering() {
        #expect(SessionStatus.waitingConfirmation.priority > SessionStatus.executing.priority)
        #expect(SessionStatus.executing.priority > SessionStatus.thinking.priority)
        #expect(SessionStatus.thinking.priority > SessionStatus.completed.priority)
        #expect(SessionStatus.completed.priority > SessionStatus.idle.priority)
        #expect(SessionStatus.error("x").priority > SessionStatus.executing.priority)
    }

    @Test("highest returns highest priority status")
    func highestPriority() {
        let statuses: [SessionStatus] = [.idle, .executing, .thinking]
        #expect(SessionStatus.highest(statuses) == .executing)
    }

    @Test("highest with waitingConfirmation wins over executing")
    func highestWithWaiting() {
        let statuses: [SessionStatus] = [.executing, .waitingConfirmation, .thinking]
        #expect(SessionStatus.highest(statuses) == .waitingConfirmation)
    }

    @Test("highest of empty array returns idle")
    func highestEmpty() {
        #expect(SessionStatus.highest([]) == .idle)
    }
}
