import Testing
import Foundation
@testable import AgentIsland

@Suite("IPCProtocol Tests")
struct IPCProtocolTests {

    @Test("HookMessage encode/decode roundtrip")
    func hookMessageRoundtrip() throws {
        let msg = HookMessage(
            type: "PermissionRequest",
            sessionId: "abc-123",
            toolName: "Bash",
            toolInput: ["command": AnyCodable("ls -la"), "timeout": AnyCodable(120000)],
            permissionLevel: "default"
        )
        let data = try IPCProtocol.encode(msg)
        let decoded = try IPCProtocol.decodeHookMessage(from: data)

        #expect(decoded.type == "PermissionRequest")
        #expect(decoded.sessionId == "abc-123")
        #expect(decoded.toolName == "Bash")
        #expect(decoded.toolInput["command"] == AnyCodable("ls -la"))
        #expect(decoded.toolInput["timeout"] == AnyCodable(120000))
        #expect(decoded.permissionLevel == "default")
    }

    @Test("HookMessage with nil permissionLevel")
    func hookMessageNilPermissionLevel() throws {
        let msg = HookMessage(
            type: "PermissionRequest",
            sessionId: "xyz",
            toolName: "Write",
            toolInput: ["file_path": AnyCodable("/tmp/test.txt")],
            permissionLevel: nil
        )
        let data = try IPCProtocol.encode(msg)
        let decoded = try IPCProtocol.decodeHookMessage(from: data)

        #expect(decoded.permissionLevel == nil)
        #expect(decoded.toolName == "Write")
    }

    @Test("HookResponse encode/decode roundtrip")
    func hookResponseRoundtrip() throws {
        let allow = HookResponse(decision: "allow", reason: nil)
        let allowData = try IPCProtocol.encode(allow)
        let decodedAllow = try IPCProtocol.decodeHookResponse(from: allowData)
        #expect(decodedAllow.decision == "allow")
        #expect(decodedAllow.reason == nil)

        let deny = HookResponse(decision: "deny", reason: "Blocked by policy")
        let denyData = try IPCProtocol.encode(deny)
        let decodedDeny = try IPCProtocol.decodeHookResponse(from: denyData)
        #expect(decodedDeny.decision == "deny")
        #expect(decodedDeny.reason == "Blocked by policy")
    }

    @Test("HookMessage uses correct JSON key names")
    func hookMessageKeyNames() throws {
        let msg = HookMessage(
            type: "PermissionRequest",
            sessionId: "s1",
            toolName: "Read",
            toolInput: [:],
            permissionLevel: nil
        )
        let data = try JSONEncoder().encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["hook_event_name"] as? String == "PermissionRequest")
        #expect(json["session_id"] as? String == "s1")
        #expect(json["tool_name"] as? String == "Read")
        #expect(json["tool_input"] != nil)
        #expect(json["permission_level"] == nil || json["permission_level"] is NSNull)
    }

    @Test("decode invalid JSON throws")
    func decodeInvalidJSON() {
        let badData = Data("not json".utf8)
        #expect(throws: (any Error).self) {
            try IPCProtocol.decodeHookMessage(from: badData)
        }
    }

    @Test("encode appends newline delimiter")
    func encodeAppendsNewline() throws {
        let resp = HookResponse(decision: "ask", reason: nil)
        let data = try IPCProtocol.encode(resp)
        #expect(data.last == 0x0A)
    }
}
