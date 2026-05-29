import Testing
import Foundation
@testable import AgentIsland

@Suite("ConfirmationQueue Tests")
struct ConfirmationQueueTests {

    private func makeSession(id: String = "s1") -> AgentSession {
        AgentSession(
            id: id,
            agentType: .qoderWork,
            title: "Task",
            status: .waitingConfirmation,
            startTime: Date(),
            lastUpdate: Date(),
            terminalInfo: nil,
            currentToolCall: nil
        )
    }

    private func makeConfirmation(id: String, secondsAgo: TimeInterval = 0) -> PendingConfirmation {
        PendingConfirmation(
            id: id,
            type: .permission,
            title: "Edit file",
            details: .permission(PermissionDetails(toolName: "Edit", operation: "edit", diff: [], additions: 1, deletions: 0)),
            timestamp: Date().addingTimeInterval(-secondsAgo)
        )
    }

    @Test("initial queue is empty")
    @MainActor
    func initialQueueIsEmpty() {
        let queue = ConfirmationQueue()
        #expect(queue.isEmpty)
        #expect(queue.count == 0)
        #expect(queue.currentItem == nil)
    }

    @Test("update populates from confirmations")
    @MainActor
    func updatePopulatesFromConfirmations() {
        let queue = ConfirmationQueue()
        let session = makeSession(id: "s1")
        let conf = makeConfirmation(id: "c1")

        queue.update(from: ["s1": [conf]], sessions: [session])

        #expect(queue.count == 1)
        #expect(queue.currentItem?.confirmation.id == "c1")
    }

    @Test("update sorts by timestamp oldest first")
    @MainActor
    func updateSortsByTimestamp() {
        let queue = ConfirmationQueue()
        let session = makeSession(id: "s1")
        let older = makeConfirmation(id: "old", secondsAgo: 10)
        let newer = makeConfirmation(id: "new", secondsAgo: 0)

        queue.update(from: ["s1": [newer, older]], sessions: [session])

        #expect(queue.items[0].confirmation.id == "old")
        #expect(queue.items[1].confirmation.id == "new")
    }

    @Test("currentItem returns item at currentIndex")
    @MainActor
    func currentItemReturnsFirstItem() {
        let queue = ConfirmationQueue()
        let session = makeSession(id: "s1")
        let conf = makeConfirmation(id: "c1")

        queue.update(from: ["s1": [conf]], sessions: [session])

        #expect(queue.currentIndex == 0)
        #expect(queue.currentItem?.id == "c1")
    }

    @Test("advance moves to next item")
    @MainActor
    func advanceMovesToNext() {
        let queue = ConfirmationQueue()
        let session = makeSession(id: "s1")
        let c1 = makeConfirmation(id: "c1", secondsAgo: 10)
        let c2 = makeConfirmation(id: "c2", secondsAgo: 0)

        queue.update(from: ["s1": [c1, c2]], sessions: [session])
        queue.advance()

        #expect(queue.currentIndex == 1)
        #expect(queue.currentItem?.id == "c2")
    }

    @Test("advance at end clears queue")
    @MainActor
    func advanceClearsAtEnd() {
        let queue = ConfirmationQueue()
        let session = makeSession(id: "s1")
        let conf = makeConfirmation(id: "c1")

        queue.update(from: ["s1": [conf]], sessions: [session])
        queue.advance()

        #expect(queue.isEmpty)
        #expect(queue.currentItem == nil)
    }

    @Test("update preserves currentIndex if current item still present")
    @MainActor
    func updatePreservesCurrentIfStillPresent() {
        let queue = ConfirmationQueue()
        let session = makeSession(id: "s1")
        let c1 = makeConfirmation(id: "c1", secondsAgo: 20)
        let c2 = makeConfirmation(id: "c2", secondsAgo: 10)

        queue.update(from: ["s1": [c1, c2]], sessions: [session])
        queue.advance()
        #expect(queue.currentItem?.id == "c2")

        let c3 = makeConfirmation(id: "c3", secondsAgo: 0)
        queue.update(from: ["s1": [c1, c2, c3]], sessions: [session])

        #expect(queue.currentItem?.id == "c2")
    }

    @Test("update advances if current item removed")
    @MainActor
    func updateAdvancesIfCurrentRemoved() {
        let queue = ConfirmationQueue()
        let session = makeSession(id: "s1")
        let c1 = makeConfirmation(id: "c1", secondsAgo: 20)
        let c2 = makeConfirmation(id: "c2", secondsAgo: 10)
        let c3 = makeConfirmation(id: "c3", secondsAgo: 0)

        queue.update(from: ["s1": [c1, c2, c3]], sessions: [session])
        queue.advance()
        #expect(queue.currentItem?.id == "c2")

        queue.update(from: ["s1": [c1, c3]], sessions: [session])

        #expect(queue.currentItem?.id == "c3")
    }

    @Test("empty after all confirmations removed")
    @MainActor
    func emptyAfterAllRemoved() {
        let queue = ConfirmationQueue()
        let session = makeSession(id: "s1")
        let conf = makeConfirmation(id: "c1")

        queue.update(from: ["s1": [conf]], sessions: [session])
        #expect(!queue.isEmpty)

        queue.update(from: [:], sessions: [session])

        #expect(queue.isEmpty)
        #expect(queue.currentItem == nil)
    }

    @Test("update populates choice-type confirmation with multiSelect")
    @MainActor
    func updatePopulatesChoiceConfirmation() {
        let queue = ConfirmationQueue()
        let session = makeSession(id: "s1")
        let choiceConf = PendingConfirmation(
            id: "choice-1",
            type: .choice,
            title: "Which features?",
            details: .choice(ChoiceDetails(
                question: "Which features?",
                header: "Features",
                options: [
                    ChoiceOption(id: "Auth", label: "Auth", description: "Authentication"),
                    ChoiceOption(id: "DB", label: "DB", description: "Database"),
                ],
                multiSelect: true
            )),
            timestamp: Date()
        )

        queue.update(from: ["s1": [choiceConf]], sessions: [session])

        #expect(queue.count == 1)
        #expect(queue.currentItem?.confirmation.id == "choice-1")
        #expect(queue.currentItem?.confirmation.type == .choice)

        if case .choice(let details) = queue.currentItem?.confirmation.details {
            #expect(details.multiSelect == true)
            #expect(details.options.count == 2)
            #expect(details.question == "Which features?")
        } else {
            Issue.record("Expected .choice details")
        }
    }
}
