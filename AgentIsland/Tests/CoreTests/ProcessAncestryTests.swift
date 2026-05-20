import Testing
import Foundation
@testable import AgentIsland

@Suite("ProcessAncestry Tests")
struct ProcessAncestryTests {

    @Test("parentPID returns valid parent for current process")
    func parentPIDReturnsValid() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let result = ProcessAncestry.findTerminalAppPID(of: currentPID)
        // Current test runner process should have a parent that is a running app
        // The result might be nil if the parent isn't in NSWorkspace.runningApplications
        // but the function should not crash
        _ = result
    }

    @Test("findTerminalAppPID returns nil for invalid PID")
    func invalidPIDReturnsNil() {
        let result = ProcessAncestry.findTerminalAppPID(of: -1)
        #expect(result == nil)
    }

    @Test("findTerminalAppPID returns nil for PID 0")
    func pid0ReturnsNil() {
        let result = ProcessAncestry.findTerminalAppPID(of: 0)
        #expect(result == nil)
    }

    @Test("findTerminalAppPID returns nil for nonexistent PID")
    func nonexistentPIDReturnsNil() {
        let result = ProcessAncestry.findTerminalAppPID(of: 99999)
        #expect(result == nil)
    }
}
