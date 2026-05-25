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
    @Test("mouseExited cancels pending expand and keeps collapsed")
    func mouseExitedCancels() {
        let state = PanelState(settingsStore: makeStore(hoverDelay: 1.0))
        state.mouseEntered()
        state.mouseExited()
        #expect(state.isExpanded == false)
    }

    @MainActor
    @Test("autoExpand sets expanded and starts auto-collapse timer")
    func autoExpandSetsExpanded() {
        let state = PanelState(settingsStore: makeStore(), autoCollapseDelay: 10.0)
        state.autoExpand()
        #expect(state.isExpanded == true)
    }

    @MainActor
    @Test("autoExpand auto-collapses after delay")
    func autoExpandAutoCollapses() {
        let state = PanelState(settingsStore: makeStore(), autoCollapseDelay: 0.1)
        state.autoExpand()
        #expect(state.isExpanded == true)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        #expect(state.isExpanded == false)
    }

    @MainActor
    @Test("mouseEntered cancels auto-collapse timer")
    func mouseEnteredCancelsAutoCollapse() {
        let state = PanelState(settingsStore: makeStore(), autoCollapseDelay: 0.1)
        state.autoExpand()
        state.mouseEntered()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        #expect(state.isExpanded == true)
    }

    @MainActor
    @Test("mouseExited collapses immediately after autoExpand")
    func mouseExitedAfterAutoExpand() {
        let store = makeStore()
        store.autoCollapseOnMouseExit = true
        let state = PanelState(settingsStore: store, mouseExitDelay: 0.1, autoCollapseDelay: 10.0)
        state.autoExpand()
        state.mouseEntered()
        state.mouseExited()
        #expect(state.isExpanded == false)
    }

    @MainActor
    @Test("mouseExited collapses immediately")
    func mouseExitedCollapsesImmediately() {
        let store = makeStore()
        store.autoCollapseOnMouseExit = true
        let state = PanelState(settingsStore: store, mouseExitDelay: 0.1)
        state.expand()
        state.mouseExited()
        #expect(state.isExpanded == false)
    }

    @MainActor
    @Test("mouseEntered after mouseExited re-expands panel")
    func mouseEnteredReexpands() {
        let store = makeStore()
        store.autoCollapseOnMouseExit = true
        let state = PanelState(settingsStore: store, mouseExitDelay: 0.1)
        state.expand()
        state.mouseExited()
        #expect(state.isExpanded == false)
        state.mouseEntered()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        #expect(state.isExpanded == true)
    }

    @MainActor
    @Test("mouseExited does not collapse when autoCollapseOnMouseExit is false")
    func mouseExitedNoCollapseWhenDisabled() {
        let store = makeStore()
        store.autoCollapseOnMouseExit = false
        let state = PanelState(settingsStore: store, mouseExitDelay: 0.1)
        state.expand()
        state.mouseExited()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        #expect(state.isExpanded == true)
    }
}
