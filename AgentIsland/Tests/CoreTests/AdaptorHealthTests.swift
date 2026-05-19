import Testing
import Foundation
@testable import AgentIsland

@Suite("AdaptorHealth Tests")
struct AdaptorHealthTests {

    @Test("initial state has no entries")
    @MainActor
    func initialStateEmpty() {
        let health = AdaptorHealth()
        #expect(health.states.isEmpty)
        #expect(health.shouldPoll(for: .qoderWork) == true)
    }

    @Test("recordSuccess sets state to online")
    @MainActor
    func recordSuccessSetsOnline() {
        let health = AdaptorHealth()
        health.recordSuccess(for: .qoderWork)
        #expect(health.states[.qoderWork] == .online)
    }

    @Test("single failure sets retrying state")
    @MainActor
    func singleFailureSetsRetrying() {
        let health = AdaptorHealth(maxFailures: 3)
        let state = health.recordFailure(for: .qoderWork)
        #expect(state == .retrying(attempt: 1))
        #expect(health.shouldPoll(for: .qoderWork) == true)
    }

    @Test("max failures sets offline state")
    @MainActor
    func maxFailuresSetsOffline() {
        let health = AdaptorHealth(maxFailures: 3)
        health.recordFailure(for: .qoderWork)
        health.recordFailure(for: .qoderWork)
        let state = health.recordFailure(for: .qoderWork)
        #expect(state == .offline)
        #expect(health.shouldPoll(for: .qoderWork) == false)
    }

    @Test("shouldPoll returns true after pause duration")
    @MainActor
    func shouldPollAfterPause() {
        let health = AdaptorHealth(maxFailures: 1, offlinePauseDuration: 0.01)
        health.recordFailure(for: .qoderWork)
        #expect(health.shouldPoll(for: .qoderWork) == false)

        Thread.sleep(forTimeInterval: 0.02)

        #expect(health.shouldPoll(for: .qoderWork) == true)
    }

    @Test("recordSuccess after offline resets to online")
    @MainActor
    func successAfterOfflineResets() {
        let health = AdaptorHealth(maxFailures: 2)
        health.recordFailure(for: .qoderWork)
        health.recordFailure(for: .qoderWork)
        #expect(health.states[.qoderWork] == .offline)

        health.recordSuccess(for: .qoderWork)
        #expect(health.states[.qoderWork] == .online)
        #expect(health.shouldPoll(for: .qoderWork) == true)
    }

    @Test("isAnyOffline reflects adaptor states")
    @MainActor
    func isAnyOfflineReflects() {
        let health = AdaptorHealth(maxFailures: 1)
        #expect(health.isAnyOffline == false)

        health.recordFailure(for: .qoderWork)
        #expect(health.isAnyOffline == true)

        health.recordSuccess(for: .qoderWork)
        #expect(health.isAnyOffline == false)
    }
}
