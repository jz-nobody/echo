import Foundation
import Testing
@testable import AgentIsland

@Suite("CodexDesktopStateParser Tests")
struct CodexDesktopStateParserTests {

    @Test("reads Codex sidebar thread names from the session index")
    func readsSessionIndexThreadNames() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexSessionIndex-\(UUID().uuidString).jsonl").path
        let jsonl = """
        {"id":"thread-1","thread_name":"旧标题","updated_at":"2026-08-01T00:00:00Z"}
        {"id":"thread-2","thread_name":"   ","updated_at":"2026-08-01T00:00:00Z"}
        {"id":"thread-1","thread_name":"继续修复 Skill 市场 QA 问题","updated_at":"2026-08-04T00:00:00Z"}
        {"id":42,"thread_name":"ignored"}
        malformed
        """
        try jsonl.write(toFile: path, atomically: true, encoding: .utf8)

        #expect(CodexDesktopStateParser.threadNames(atPath: path) == [
            "thread-1": "继续修复 Skill 市场 QA 问题"
        ])
    }

    @Test("reads non-empty Codex sidebar thread descriptions")
    func readsDescriptions() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexDesktopState-\(UUID().uuidString).json").path
        let json = #"{"electron-persisted-atom-state":{"thread-descriptions-v1":{"thread-1":"继续修复 Skill 市场 QA","thread-2":"   ","thread-3":42}}}"#
        try json.write(toFile: path, atomically: true, encoding: .utf8)

        #expect(CodexDesktopStateParser.threadDescriptions(atPath: path) == [
            "thread-1": "继续修复 Skill 市场 QA"
        ])
    }
}
