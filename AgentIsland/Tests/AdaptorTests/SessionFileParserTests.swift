import Testing
import Foundation
@testable import AgentIsland

@Suite("SessionFileParser Tests")
struct SessionFileParserTests {

    private let validJSON = """
    {
      "pid": 72727,
      "sessionId": "9327accc-a0d6-478c-9616-2764d4035390",
      "cwd": "/Users/dev/my-project",
      "startedAt": 1779212717359,
      "version": "2.1.144",
      "peerProtocol": 1,
      "kind": "interactive",
      "entrypoint": "claude-vscode"
    }
    """.data(using: .utf8)!

    private let validJSONWithStatus = """
    {
      "pid": 93514,
      "sessionId": "9d515e53-207f-47c7-958e-66994a3d407a",
      "cwd": "/Users/dev",
      "startedAt": 1779217378425,
      "version": "2.1.133",
      "peerProtocol": 1,
      "kind": "interactive",
      "entrypoint": "cli",
      "status": "idle",
      "updatedAt": 1779217685385
    }
    """.data(using: .utf8)!

    @Test("parse valid session JSON with all fields")
    func parseValidJSON() throws {
        let session = SessionFileParser.parse(data: validJSONWithStatus)
        let s = try #require(session)

        #expect(s.pid == 93514)
        #expect(s.sessionId == "9d515e53-207f-47c7-958e-66994a3d407a")
        #expect(s.cwd == "/Users/dev")
        #expect(s.startedAt == 1779217378425)
        #expect(s.version == "2.1.133")
        #expect(s.kind == "interactive")
        #expect(s.entrypoint == "cli")
        #expect(s.status == "idle")
        #expect(s.updatedAt == 1779217685385)
    }

    @Test("parse session JSON with missing optional fields")
    func parseMissingOptionals() throws {
        let session = SessionFileParser.parse(data: validJSON)
        let s = try #require(session)

        #expect(s.pid == 72727)
        #expect(s.sessionId == "9327accc-a0d6-478c-9616-2764d4035390")
        #expect(s.entrypoint == "claude-vscode")
        #expect(s.status == nil)
        #expect(s.updatedAt == nil)
    }

    @Test("parse invalid JSON returns nil")
    func parseInvalidJSON() {
        let badData = Data("not json".utf8)
        #expect(SessionFileParser.parse(data: badData) == nil)
    }

    @Test("toAgentSession extracts project name from cwd")
    func toAgentSessionProjectName() {
        let session = SessionFileParser.parse(data: validJSON)!
        let agent = SessionFileParser.toAgentSession(session)

        #expect(agent.title == "my-project")
        #expect(agent.agentType == .claudeCode)
        #expect(agent.id == "9327accc-a0d6-478c-9616-2764d4035390")
        #expect(agent.terminalInfo?.appName == "claude-vscode")
        #expect(agent.terminalInfo?.pid == 72727)
    }

    @Test("toAgentSession maps idle status correctly")
    func toAgentSessionIdleStatus() {
        let session = SessionFileParser.parse(data: validJSONWithStatus)!
        let agent = SessionFileParser.toAgentSession(session)

        #expect(agent.status == .idle)
    }

    @Test("toAgentSession maps non-idle status to executing")
    func toAgentSessionExecutingStatus() {
        let session = SessionFileParser.parse(data: validJSON)!
        let agent = SessionFileParser.toAgentSession(session)

        #expect(agent.status == .executing)
    }

    @Test("toAgentSession converts startedAt millis to Date")
    func toAgentSessionStartTime() {
        let session = SessionFileParser.parse(data: validJSON)!
        let agent = SessionFileParser.toAgentSession(session)
        let expectedDate = Date(timeIntervalSince1970: 1779212717.359)

        #expect(abs(agent.startTime.timeIntervalSince(expectedDate)) < 0.001)
    }
}
