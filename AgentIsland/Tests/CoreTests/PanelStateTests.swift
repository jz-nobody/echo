import Foundation
import Testing
@testable import AgentIsland

@Suite("PanelState Tests")
struct PanelStateTests {

    @MainActor
    private func makeStore(hoverDelay: TimeInterval = 0.15) -> SettingsStore {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "test-panelstate-\(UUID())")!)
        store.hoverDelay = hoverDelay
        return store
    }

    @MainActor
    @Test("initial state is collapsed")
    func initialState() {
        let state = PanelState(settingsStore: makeStore())
        #expect(state.isExpanded == false)
    }

    @MainActor
    @Test("expand sets isExpanded to true")
    func expand() {
        let state = PanelState(settingsStore: makeStore())
        state.expand()
        #expect(state.isExpanded == true)
    }

    @MainActor
    @Test("collapse sets isExpanded to false")
    func collapse() {
        let state = PanelState(settingsStore: makeStore())
        state.expand()
        state.collapse()
        #expect(state.isExpanded == false)
    }

    @MainActor
    @Test("toggle flips state")
    func toggle() {
        let state = PanelState(settingsStore: makeStore())
        state.toggle()
        #expect(state.isExpanded == true)
        state.toggle()
        #expect(state.isExpanded == false)
    }

    @MainActor
    @Test("mouseExited cancels pending expand and collapses")
    func mouseExitedCancels() {
        let state = PanelState(settingsStore: makeStore(hoverDelay: 1.0))
        state.mouseEntered()
        state.mouseExited()
        #expect(state.isExpanded == false)
    }

    @MainActor
    @Test("autoExpand sets expanded and confirmationsActive")
    func autoExpandSetsExpandedAndFlag() {
        let state = PanelState(settingsStore: makeStore())
        state.autoExpand()
        #expect(state.isExpanded == true)
        #expect(state.confirmationsActive == true)
    }

    @MainActor
    @Test("mouseExited stays expanded when confirmations active")
    func mouseExitedStaysExpandedWhenConfirmationsActive() {
        let state = PanelState(settingsStore: makeStore())
        state.autoExpand()
        state.mouseExited()
        #expect(state.isExpanded == true)
    }

    @MainActor
    @Test("mouseExited starts delayed collapse, does not collapse immediately")
    func mouseExitedDelayedCollapse() {
        let store = makeStore()
        store.autoCollapseOnMouseExit = true
        let state = PanelState(settingsStore: store, autoCollapseDelay: 5.0)
        state.expand()
        state.mouseExited()
        #expect(state.isExpanded == true)
    }

    @MainActor
    @Test("mouseEntered cancels pending collapse timer")
    func mouseEnteredCancelsCollapse() {
        let store = makeStore()
        store.autoCollapseOnMouseExit = true
        let state = PanelState(settingsStore: store, autoCollapseDelay: 0.1)
        state.expand()
        state.mouseExited()
        #expect(state.isExpanded == true)
        state.mouseEntered()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        #expect(state.isExpanded == true)
    }

    @MainActor
    @Test("mouseExited collapses panel after delay elapses")
    func mouseExitedCollapsesAfterDelay() {
        let store = makeStore()
        store.autoCollapseOnMouseExit = true
        let state = PanelState(settingsStore: store, autoCollapseDelay: 0.1)
        state.expand()
        state.mouseExited()
        #expect(state.isExpanded == true)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        #expect(state.isExpanded == false)
    }

    @MainActor
    @Test("mouseExited does not collapse when autoCollapseOnMouseExit is false")
    func mouseExitedNoCollapseWhenDisabled() {
        let store = makeStore()
        store.autoCollapseOnMouseExit = false
        let state = PanelState(settingsStore: store, autoCollapseDelay: 0.1)
        state.expand()
        state.mouseExited()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        #expect(state.isExpanded == true)
    }
}
