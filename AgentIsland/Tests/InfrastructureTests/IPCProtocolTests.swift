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
        #expect(decoded.toolInput?["command"] == AnyCodable("ls -la"))
        #expect(decoded.toolInput?["timeout"] == AnyCodable(120000))
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

    @Test("HookMessage decode without tool fields succeeds")
    func decodeHookMessageWithoutToolFields() throws {
        let json = """
        {"hook_event_name":"PreCompact","session_id":"s99"}
        """
        let decoded = try IPCProtocol.decodeHookMessage(from: Data(json.utf8))
        #expect(decoded.type == "PreCompact")
        #expect(decoded.sessionId == "s99")
        #expect(decoded.toolName == nil)
        #expect(decoded.toolInput == nil)
        #expect(decoded.permissionLevel == nil)
    }

    @Test("HookResponse.empty encodes to empty JSON object")
    func hookResponseEmptyEncoding() throws {
        let data = try JSONEncoder().encode(HookResponse.empty)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json.isEmpty)
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

    @Test("HookResponse allow encodes to Claude Code hookSpecificOutput format")
    func hookResponseAllowFormat() throws {
        let allow = HookResponse(decision: "allow", reason: nil)
        let data = try JSONEncoder().encode(allow)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["continue"] as? Bool == true)
        #expect(json["suppressOutput"] as? Bool == true)
        let output = json["hookSpecificOutput"] as! [String: Any]
        #expect(output["hookEventName"] as? String == "PermissionRequest")
        let decision = output["decision"] as! [String: Any]
        #expect(decision["behavior"] as? String == "allow")
    }

    @Test("HookResponse deny encodes with message")
    func hookResponseDenyFormat() throws {
        let deny = HookResponse(decision: "deny", reason: "Not allowed")
        let data = try JSONEncoder().encode(deny)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let output = json["hookSpecificOutput"] as! [String: Any]
        let decision = output["decision"] as! [String: Any]
        #expect(decision["behavior"] as? String == "deny")
        #expect(decision["message"] as? String == "Not allowed")
    }

    @Test("HookResponse.question encodes updatedInput in decision")
    func hookResponseQuestionFormat() throws {
        let originalInput: [String: AnyCodable] = [
            "questions": AnyCodable([
                ["question": "Which color?", "options": [["label": "Red"], ["label": "Blue"]]]
            ])
        ]
        let resp = HookResponse.question(answers: ["Which color?": "Red"], originalInput: originalInput)
        let data = try JSONEncoder().encode(resp)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let output = json["hookSpecificOutput"] as! [String: Any]
        let decision = output["decision"] as! [String: Any]
        #expect(decision["behavior"] as? String == "allow")

        let updatedInput = decision["updatedInput"] as! [String: Any]
        let answers = updatedInput["answers"] as! [String: Any]
        #expect(answers["Which color?"] as? String == "Red")
        #expect(updatedInput["questions"] != nil)
    }

    @Test("HookResponse with updatedInput decode roundtrip")
    func hookResponseUpdatedInputRoundtrip() throws {
        let originalInput: [String: AnyCodable] = [
            "questions": AnyCodable([["question": "Pick one", "options": [["label": "A"]]]])
        ]
        let resp = HookResponse.question(answers: ["Pick one": "A"], originalInput: originalInput)
        let data = try IPCProtocol.encode(resp)
        let decoded = try IPCProtocol.decodeHookResponse(from: data)

        #expect(decoded.decision == "allow")
        #expect(decoded.updatedInput != nil)
        let answers = decoded.updatedInput?["answers"]?.value as? [String: Any]
        #expect(answers?["Pick one"] as? String == "A")
    }

    @Test("HookMessage decodes prompt field")
    func hookMessageDecodesPrompt() throws {
        let json = """
        {"hook_event_name":"UserPromptSubmit","session_id":"s1","prompt":"Hello world"}
        """
        let decoded = try IPCProtocol.decodeHookMessage(from: Data(json.utf8))
        #expect(decoded.prompt == "Hello world")
    }

    @Test("HookMessage decodes cwd field")
    func hookMessageDecodesCwd() throws {
        let json = """
        {"hook_event_name":"SessionStart","session_id":"s2","cwd":"/Users/test/project"}
        """
        let decoded = try IPCProtocol.decodeHookMessage(from: Data(json.utf8))
        #expect(decoded.cwd == "/Users/test/project")
    }

    @Test("HookMessage decodes transcript_path field")
    func hookMessageDecodesTranscriptPath() throws {
        let json = """
        {"hook_event_name":"SessionStart","session_id":"s3","transcript_path":"/tmp/sessions/abc.jsonl"}
        """
        let decoded = try IPCProtocol.decodeHookMessage(from: Data(json.utf8))
        #expect(decoded.transcriptPath == "/tmp/sessions/abc.jsonl")
    }

    @Test("HookMessage missing new fields decode as nil")
    func hookMessageMissingNewFields() throws {
        let json = """
        {"hook_event_name":"Stop","session_id":"s4"}
        """
        let decoded = try IPCProtocol.decodeHookMessage(from: Data(json.utf8))
        #expect(decoded.prompt == nil)
        #expect(decoded.cwd == nil)
        #expect(decoded.transcriptPath == nil)
    }

    @Test("HookResponse.question with multi-answer encodes comma-separated value")
    func hookResponseQuestionMultipleAnswers() throws {
        let originalInput: [String: AnyCodable] = [
            "questions": AnyCodable([
                [
                    "question": "Which features?",
                    "multiSelect": true,
                    "options": [
                        ["label": "Auth"],
                        ["label": "DB"],
                        ["label": "Cache"],
                    ],
                ]
            ])
        ]
        let resp = HookResponse.question(
            answers: ["Which features?": "Auth, Cache"],
            originalInput: originalInput
        )
        let data = try JSONEncoder().encode(resp)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let output = json["hookSpecificOutput"] as! [String: Any]
        let decision = output["decision"] as! [String: Any]
        #expect(decision["behavior"] as? String == "allow")

        let updatedInput = decision["updatedInput"] as! [String: Any]
        let answers = updatedInput["answers"] as! [String: Any]
        #expect(answers["Which features?"] as? String == "Auth, Cache")
        #expect(updatedInput["questions"] != nil)
    }
}
