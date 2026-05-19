import Testing
@testable import AgentIsland

@Suite("PanelState Tests")
struct PanelStateTests {

    @MainActor
    @Test("initial state is collapsed")
    func initialState() {
        let state = PanelState()
        #expect(state.isExpanded == false)
    }

    @MainActor
    @Test("expand sets isExpanded to true")
    func expand() {
        let state = PanelState()
        state.expand()
        #expect(state.isExpanded == true)
    }

    @MainActor
    @Test("collapse sets isExpanded to false")
    func collapse() {
        let state = PanelState()
        state.expand()
        state.collapse()
        #expect(state.isExpanded == false)
    }

    @MainActor
    @Test("toggle flips state")
    func toggle() {
        let state = PanelState()
        state.toggle()
        #expect(state.isExpanded == true)
        state.toggle()
        #expect(state.isExpanded == false)
    }

    @MainActor
    @Test("mouseExited cancels pending expand and collapses")
    func mouseExitedCancels() {
        let state = PanelState(hoverDelay: 1.0)
        state.mouseEntered()
        state.mouseExited()
        #expect(state.isExpanded == false)
    }

    @MainActor
    @Test("autoExpand sets expanded and confirmationsActive")
    func autoExpandSetsExpandedAndFlag() {
        let state = PanelState()
        state.autoExpand()
        #expect(state.isExpanded == true)
        #expect(state.confirmationsActive == true)
    }

    @MainActor
    @Test("mouseExited stays expanded when confirmations active")
    func mouseExitedStaysExpandedWhenConfirmationsActive() {
        let state = PanelState()
        state.autoExpand()
        state.mouseExited()
        #expect(state.isExpanded == true)
    }
}
