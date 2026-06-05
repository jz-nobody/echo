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
    @Test("mouseEntered after autoExpand cancels auto-collapse timer")
    func mouseEnteredCancelsAutoCollapse() {
        let state = PanelState(settingsStore: makeStore(), autoCollapseDelay: 10.0)
        state.autoExpand()
        state.mouseEntered()
        #expect(state.autoExpandedAt == nil)
        #expect(state.isExpanded == true)
    }

    @MainActor
    @Test("mouseEntered during autoExpand switches to hover mode")
    func mouseEnteredDuringAutoExpandSwitchesToHover() {
        let state = PanelState(settingsStore: makeStore(), autoCollapseDelay: 0.15)
        state.autoExpand()
        state.mouseEntered()
        #expect(state.autoExpandedAt == nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        #expect(state.isExpanded == true)
    }

    @MainActor
    @Test("mouseExited during autoExpand does not collapse immediately")
    func mouseExitedDuringAutoExpand() {
        let store = makeStore()
        store.autoCollapseOnMouseExit = true
        let state = PanelState(settingsStore: store, autoCollapseDelay: 10.0)
        state.autoExpand()
        state.mouseExited()
        #expect(state.isExpanded == true)
    }

    @MainActor
    @Test("autoExpand mouseEntered then mouseExited collapses immediately")
    func autoExpandMouseEnteredThenExitedCollapses() {
        let store = makeStore()
        store.autoCollapseOnMouseExit = true
        let state = PanelState(settingsStore: store, autoCollapseDelay: 10.0)
        state.autoExpand()
        state.mouseEntered()
        state.mouseExited()
        #expect(state.isExpanded == false)
    }

    @MainActor
    @Test("normal hover expand not affected by autoExpandedAt")
    func normalHoverNotAffected() {
        let store = makeStore()
        store.autoCollapseOnMouseExit = true
        let state = PanelState(settingsStore: store, mouseExitDelay: 0.1)
        state.expand()
        #expect(state.autoExpandedAt == nil)
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

    @MainActor
    @Test("mouseExited does not collapse when wasAutoExpandedForConfirmation is true")
    func mouseExitedSkipsConfirmationPanel() {
        let store = makeStore()
        store.autoCollapseOnMouseExit = true
        let state = PanelState(settingsStore: store)
        state.expandForConfirmation()
        #expect(state.isExpanded == true)
        state.mouseExited()
        #expect(state.isExpanded == true)
    }

    @MainActor
    @Test("mouseExited collapses normally when wasAutoExpandedForConfirmation is false")
    func mouseExitedCollapsesNonConfirmationPanel() {
        let store = makeStore()
        store.autoCollapseOnMouseExit = true
        let state = PanelState(settingsStore: store)
        state.expand()
        #expect(state.wasAutoExpandedForConfirmation == false)
        state.mouseExited()
        #expect(state.isExpanded == false)
    }

    @MainActor
    @Test("expandForConfirmation sets expanded and wasAutoExpandedForConfirmation")
    func expandForConfirmation() {
        let state = PanelState(settingsStore: makeStore())
        state.expandForConfirmation()
        #expect(state.isExpanded == true)
        #expect(state.wasAutoExpandedForConfirmation == true)
    }

    @MainActor
    @Test("expandForConfirmation does not auto-collapse")
    func expandForConfirmationNoAutoCollapse() {
        let state = PanelState(settingsStore: makeStore(), autoCollapseDelay: 0.1)
        state.expandForConfirmation()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        #expect(state.isExpanded == true)
    }

    @MainActor
    @Test("manual expand clears wasAutoExpandedForConfirmation")
    func manualExpandClearsFlag() {
        let state = PanelState(settingsStore: makeStore())
        state.expandForConfirmation()
        #expect(state.wasAutoExpandedForConfirmation == true)
        state.collapse()
        state.expand()
        #expect(state.wasAutoExpandedForConfirmation == false)
    }

    @MainActor
    @Test("delayedCollapse collapses after delay")
    func delayedCollapseWorks() {
        let state = PanelState(settingsStore: makeStore())
        state.expandForConfirmation()
        state.delayedCollapse()
        #expect(state.isExpanded == true)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.0))
        #expect(state.isExpanded == false)
        #expect(state.wasAutoExpandedForConfirmation == false)
    }

    @MainActor
    @Test("collapse resets wasAutoExpandedForConfirmation")
    func collapseResetsFlag() {
        let state = PanelState(settingsStore: makeStore())
        state.expandForConfirmation()
        state.collapse()
        #expect(state.wasAutoExpandedForConfirmation == false)
    }
}
