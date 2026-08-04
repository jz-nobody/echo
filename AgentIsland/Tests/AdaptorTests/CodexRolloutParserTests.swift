import Testing
import Foundation
@testable import AgentIsland

@Suite("CodexRolloutParser Tests")
struct CodexRolloutParserTests {

    private func writeTempRollout(_ lines: [String]) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexRollout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("rollout.jsonl").path
        try (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func userLine(_ text: String) -> String {
        let payload: [String: Any] = [
            "type": "message", "role": "user",
            "content": [["type": "input_text", "text": text]],
        ]
        let obj: [String: Any] = ["type": "response_item", "payload": payload]
        let data = try! JSONSerialization.data(withJSONObject: obj)
        return String(data: data, encoding: .utf8)!
    }

    @Test("returns latest genuine user message")
    func latestGenuine() throws {
        let path = try writeTempRollout([
            userLine("第一个问题"),
            #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"回复"}]}}"#,
            userLine("最新的真实问题"),
        ])
        #expect(CodexRolloutParser.lastUserPrompt(atPath: path) == "最新的真实问题")
    }

    @Test("skips injected environment_context and file preambles")
    func skipsInjected() throws {
        let path = try writeTempRollout([
            userLine("真实问题在这里"),
            userLine("<environment_context>\n  <current_date>2026-07-30</current_date>\n</environment_context>"),
            userLine("# Files mentioned by the user:\n\n## foo.swift"),
        ])
        #expect(CodexRolloutParser.lastUserPrompt(atPath: path) == "真实问题在这里")
    }

    @Test("finds message beyond a single tail chunk")
    func deepScan() throws {
        let filler = #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":""#
            + String(repeating: "x", count: 400_000) + #""}]}}"#
        let path = try writeTempRollout([
            userLine("被大量输出挤到后面的真实问题"),
            filler,
        ])
        #expect(CodexRolloutParser.lastUserPrompt(atPath: path) == "被大量输出挤到后面的真实问题")
    }

    @Test("nil when no genuine user message")
    func noGenuine() throws {
        let path = try writeTempRollout([
            userLine("<environment_context>ctx</environment_context>"),
        ])
        #expect(CodexRolloutParser.lastUserPrompt(atPath: path) == nil)
    }

    @Test("latest task_started means the Codex turn is active")
    func activeTurn() throws {
        let path = try writeTempRollout([
            #"{"type":"event_msg","payload":{"type":"task_complete"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
        ])
        #expect(CodexRolloutParser.latestTurnState(atPath: path) == .active)
    }

    @Test("task completion and abort close the Codex turn")
    func inactiveTurn() throws {
        let completed = try writeTempRollout([
            #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_complete"}}"#,
        ])
        let aborted = try writeTempRollout([
            #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"type":"event_msg","payload":{"type":"turn_aborted"}}"#,
        ])
        #expect(CodexRolloutParser.latestTurnState(atPath: completed) == .inactive)
        #expect(CodexRolloutParser.latestTurnState(atPath: aborted) == .inactive)
    }
}
