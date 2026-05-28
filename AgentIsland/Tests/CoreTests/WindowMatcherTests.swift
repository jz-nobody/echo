import Testing
import Foundation
@testable import AgentIsland

@Suite("WindowMatcher Tests")
struct WindowMatcherTests {

    // MARK: - selectTarget: exact segment match

    @Test("selects window with exact segment match")
    func exactSegmentMatch() {
        let windows = [
            WindowCandidate(index: 0, title: "user@mac — ~/.config — zsh", isMinimized: false, isMain: true),
            WindowCandidate(index: 1, title: "user@mac — echo — zsh", isMinimized: false, isMain: false),
            WindowCandidate(index: 2, title: "user@mac — other-project — zsh", isMinimized: true, isMain: false),
        ]

        let result = WindowMatcher.selectTarget(windows: windows, sessionTitle: "echo")
        #expect(result == 1)
    }

    @Test("exact segment match is case insensitive")
    func exactSegmentCaseInsensitive() {
        let windows = [
            WindowCandidate(index: 0, title: "user — Echo — zsh", isMinimized: false, isMain: true),
            WindowCandidate(index: 1, title: "user — other — zsh", isMinimized: false, isMain: false),
        ]

        let result = WindowMatcher.selectTarget(windows: windows, sessionTitle: "echo")
        #expect(result == 0)
    }

    // MARK: - selectTarget: substring match fallback

    @Test("falls back to substring match when no exact segment")
    func substringMatch() {
        let windows = [
            WindowCandidate(index: 0, title: "Terminal — running task", isMinimized: false, isMain: true),
            WindowCandidate(index: 1, title: "echo-project: npm run dev", isMinimized: false, isMain: false),
        ]

        let result = WindowMatcher.selectTarget(windows: windows, sessionTitle: "echo")
        #expect(result == 1)
    }

    // MARK: - selectTarget: fallback to all windows

    @Test("falls back to all windows when no title match")
    func noMatchFallback() {
        let windows = [
            WindowCandidate(index: 0, title: "Terminal — zsh", isMinimized: false, isMain: true),
            WindowCandidate(index: 1, title: "Terminal — bash", isMinimized: false, isMain: false),
        ]

        let result = WindowMatcher.selectTarget(windows: windows, sessionTitle: "echo")
        #expect(result == 1) // prefers non-main
    }

    @Test("returns nil for empty windows")
    func emptyWindows() {
        let result = WindowMatcher.selectTarget(windows: [], sessionTitle: "echo")
        #expect(result == nil)
    }

    // MARK: - selectTarget: preference for minimized among candidates

    @Test("prefers minimized window among multiple exact matches")
    func prefersMinimizedAmongExact() {
        let windows = [
            WindowCandidate(index: 0, title: "user — echo — zsh", isMinimized: false, isMain: true),
            WindowCandidate(index: 1, title: "user — echo — vim", isMinimized: true, isMain: false),
        ]

        let result = WindowMatcher.selectTarget(windows: windows, sessionTitle: "echo")
        #expect(result == 1)
    }

    @Test("prefers non-main window when no minimized candidate")
    func prefersNonMain() {
        let windows = [
            WindowCandidate(index: 0, title: "user — echo — zsh", isMinimized: false, isMain: true),
            WindowCandidate(index: 1, title: "user — echo — vim", isMinimized: false, isMain: false),
        ]

        let result = WindowMatcher.selectTarget(windows: windows, sessionTitle: "echo")
        #expect(result == 1)
    }

    @Test("returns single candidate directly")
    func singleCandidate() {
        let windows = [
            WindowCandidate(index: 0, title: "user — echo — zsh", isMinimized: false, isMain: true),
            WindowCandidate(index: 1, title: "user — other — zsh", isMinimized: true, isMain: false),
        ]

        let result = WindowMatcher.selectTarget(windows: windows, sessionTitle: "echo")
        #expect(result == 0)
    }

    // MARK: - indicestoReminimize

    @Test("returns indices of minimized windows excluding target")
    func reminimizeExcludesTarget() {
        let snapshot = [
            WindowCandidate(index: 0, title: "A", isMinimized: true, isMain: false),
            WindowCandidate(index: 1, title: "B", isMinimized: false, isMain: true),
            WindowCandidate(index: 2, title: "C", isMinimized: true, isMain: false),
            WindowCandidate(index: 3, title: "D", isMinimized: true, isMain: false),
        ]

        let result = WindowMatcher.indicestoReminimize(before: snapshot, targetIndex: 2)
        #expect(result == [0, 3])
    }

    @Test("returns empty when no windows were minimized")
    func noMinimizedWindows() {
        let snapshot = [
            WindowCandidate(index: 0, title: "A", isMinimized: false, isMain: true),
            WindowCandidate(index: 1, title: "B", isMinimized: false, isMain: false),
        ]

        let result = WindowMatcher.indicestoReminimize(before: snapshot, targetIndex: 0)
        #expect(result.isEmpty)
    }

    @Test("returns all minimized indices when target is nil")
    func nilTargetReminimizesAll() {
        let snapshot = [
            WindowCandidate(index: 0, title: "A", isMinimized: true, isMain: false),
            WindowCandidate(index: 1, title: "B", isMinimized: true, isMain: false),
        ]

        let result = WindowMatcher.indicestoReminimize(before: snapshot, targetIndex: nil)
        #expect(result == [0, 1])
    }

    @Test("returns all other minimized when target is minimized")
    func targetWasMinimized() {
        let snapshot = [
            WindowCandidate(index: 0, title: "echo", isMinimized: true, isMain: false),
            WindowCandidate(index: 1, title: "other", isMinimized: true, isMain: false),
            WindowCandidate(index: 2, title: "another", isMinimized: true, isMain: false),
        ]

        let result = WindowMatcher.indicestoReminimize(before: snapshot, targetIndex: 0)
        #expect(result == [1, 2])
    }

    // MARK: - hasExactSegmentMatch

    @Test("matches segment split by em-dash")
    func segmentSplitByEmDash() {
        #expect(WindowMatcher.hasExactSegmentMatch(title: "user — echo — zsh", sessionTitle: "echo"))
    }

    @Test("does not match partial segment")
    func noPartialSegmentMatch() {
        #expect(!WindowMatcher.hasExactSegmentMatch(title: "user — echo-project — zsh", sessionTitle: "echo"))
    }

    @Test("does not match substring within segment")
    func noSubstringWithinSegment() {
        #expect(!WindowMatcher.hasExactSegmentMatch(title: "user — my-echo-task — zsh", sessionTitle: "echo"))
    }

    @Test("matches case insensitively")
    func caseInsensitiveSegment() {
        #expect(WindowMatcher.hasExactSegmentMatch(title: "user — ECHO — zsh", sessionTitle: "echo"))
    }

    // MARK: - Real-world Terminal.app title scenarios

    @Test("matches Terminal.app window with project name")
    func terminalAppProjectName() {
        let windows = [
            WindowCandidate(index: 0, title: "wm338658@Mac — ~/project-a — zsh", isMinimized: true, isMain: false),
            WindowCandidate(index: 1, title: "wm338658@Mac — ~/echo — zsh", isMinimized: true, isMain: false),
            WindowCandidate(index: 2, title: "wm338658@Mac — ~/project-b — zsh", isMinimized: true, isMain: false),
        ]

        let target = WindowMatcher.selectTarget(windows: windows, sessionTitle: "echo")
        #expect(target == 1)

        let toReminimize = WindowMatcher.indicestoReminimize(before: windows, targetIndex: target)
        #expect(toReminimize == [0, 2])
    }

    @Test("only target window is unminimized in multi-session scenario")
    func multiSessionOnlyTarget() {
        let windows = [
            WindowCandidate(index: 0, title: "user — echo — claude", isMinimized: false, isMain: true),
            WindowCandidate(index: 1, title: "user — project-x — qoder", isMinimized: true, isMain: false),
            WindowCandidate(index: 2, title: "user — project-y — npm", isMinimized: true, isMain: false),
            WindowCandidate(index: 3, title: "user — project-z — vim", isMinimized: true, isMain: false),
        ]

        let target = WindowMatcher.selectTarget(windows: windows, sessionTitle: "echo")
        #expect(target == 0)

        let toReminimize = WindowMatcher.indicestoReminimize(before: windows, targetIndex: target)
        #expect(toReminimize == [1, 2, 3])
    }

    @Test("VS Code window matching by workspace name")
    func vscodeWorkspaceName() {
        let windows = [
            WindowCandidate(index: 0, title: "echo — file.swift — Visual Studio Code", isMinimized: false, isMain: true),
            WindowCandidate(index: 1, title: "other-repo — main.rs — Visual Studio Code", isMinimized: true, isMain: false),
        ]

        let target = WindowMatcher.selectTarget(windows: windows, sessionTitle: "echo")
        #expect(target == 0)

        let toReminimize = WindowMatcher.indicestoReminimize(before: windows, targetIndex: target)
        #expect(toReminimize == [1])
    }

    // MARK: - Core invariant: non-target windows must never be touched

    @Test("core invariant: selectTarget returns exactly one index")
    func invariantSingleTarget() {
        let windows = [
            WindowCandidate(index: 0, title: "echo — zsh", isMinimized: true, isMain: false),
            WindowCandidate(index: 1, title: "echo — vim", isMinimized: true, isMain: false),
            WindowCandidate(index: 2, title: "project-a — zsh", isMinimized: true, isMain: false),
            WindowCandidate(index: 3, title: "project-b — zsh", isMinimized: true, isMain: false),
        ]

        let target = WindowMatcher.selectTarget(windows: windows, sessionTitle: "echo")
        #expect(target != nil)

        let toReminimize = WindowMatcher.indicestoReminimize(before: windows, targetIndex: target)
        #expect(!toReminimize.contains(target!))
        #expect(toReminimize.count == windows.count - 1)
    }

    @Test("core invariant: non-matching windows always in reminimize list")
    func invariantNonMatchingAlwaysReminimized() {
        let windows = [
            WindowCandidate(index: 0, title: "target-project — zsh", isMinimized: true, isMain: false),
            WindowCandidate(index: 1, title: "unrelated-1 — zsh", isMinimized: true, isMain: false),
            WindowCandidate(index: 2, title: "unrelated-2 — zsh", isMinimized: true, isMain: false),
        ]

        let target = WindowMatcher.selectTarget(windows: windows, sessionTitle: "target-project")
        #expect(target == 0)

        let toReminimize = WindowMatcher.indicestoReminimize(before: windows, targetIndex: target)
        #expect(toReminimize.contains(1))
        #expect(toReminimize.contains(2))
        #expect(!toReminimize.contains(0))
    }

    @Test("core invariant: non-minimized windows are never in reminimize list")
    func invariantNonMinimizedNeverReminimized() {
        let windows = [
            WindowCandidate(index: 0, title: "echo — zsh", isMinimized: false, isMain: true),
            WindowCandidate(index: 1, title: "project-a — zsh", isMinimized: false, isMain: false),
            WindowCandidate(index: 2, title: "project-b — zsh", isMinimized: true, isMain: false),
        ]

        let target = WindowMatcher.selectTarget(windows: windows, sessionTitle: "echo")
        let toReminimize = WindowMatcher.indicestoReminimize(before: windows, targetIndex: target)
        #expect(!toReminimize.contains(0))
        #expect(!toReminimize.contains(1))
        #expect(toReminimize.contains(2))
    }
}
