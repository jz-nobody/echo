@testable import AgentIsland

@MainActor
final class MockLoginItemManager: LoginItemManaging {
    private(set) var calls: [Bool] = []

    func setEnabled(_ enabled: Bool) {
        calls.append(enabled)
    }

    func reset() {
        calls = []
    }
}
