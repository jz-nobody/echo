import Foundation

enum ConversationLogParser {
    struct LastMessages: Sendable {
        let userPrompt: String?
        let assistantMessage: String?
    }

    struct ConversationSnapshot: Sendable {
        let sessionDescription: String?
        let lastUserPrompt: String?
        let lastAssistantMessage: String?
        let todos: [TodoItem]
        let subagents: [SubagentInfo]
        let permissionMode: String?
        let isConversationCompressed: Bool
    }

    private static let headReadSize: UInt64 = 8192
    private static let tailReadSize: UInt64 = 65536
    private static let maxTextLength = 200

    // MARK: - Public API

    static func snapshot(cwd: String, sessionId: String) -> ConversationSnapshot {
        let path = jsonlPath(cwd: cwd, sessionId: sessionId)
        return snapshot(atPath: path)
    }

    static func snapshot(atPath path: String) -> ConversationSnapshot {
        guard let fileHandle = FileHandle(forReadingAtPath: path) else {
            return ConversationSnapshot(sessionDescription: nil, lastUserPrompt: nil, lastAssistantMessage: nil, todos: [], subagents: [], permissionMode: nil, isConversationCompressed: false)
        }
        defer { fileHandle.closeFile() }

        let fileSize = fileHandle.seekToEndOfFile()
        guard fileSize > 0 else {
            return ConversationSnapshot(sessionDescription: nil, lastUserPrompt: nil, lastAssistantMessage: nil, todos: [], subagents: [], permissionMode: nil, isConversationCompressed: false)
        }

        let description = readSessionDescription(fileHandle: fileHandle, fileSize: fileSize)
        let tailData = readTailData(fileHandle: fileHandle, fileSize: fileSize)

        return ConversationSnapshot(
            sessionDescription: description,
            lastUserPrompt: tailData.lastUserPrompt,
            lastAssistantMessage: tailData.lastAssistantMessage,
            todos: tailData.todos,
            subagents: tailData.subagents,
            permissionMode: tailData.permissionMode,
            isConversationCompressed: tailData.isConversationCompressed
        )
    }

    static func lastMessages(cwd: String, sessionId: String) -> LastMessages {
        let snap = snapshot(cwd: cwd, sessionId: sessionId)
        return LastMessages(userPrompt: snap.lastUserPrompt, assistantMessage: snap.lastAssistantMessage)
    }

    static func lastMessages(atPath path: String) -> LastMessages {
        let snap = snapshot(atPath: path)
        return LastMessages(userPrompt: snap.lastUserPrompt, assistantMessage: snap.lastAssistantMessage)
    }

    // MARK: - Head parsing (session description)

    private static func readSessionDescription(fileHandle: FileHandle, fileSize: UInt64) -> String? {
        fileHandle.seek(toFileOffset: 0)
        let readSize = min(fileSize, headReadSize)
        let data = fileHandle.readData(ofLength: Int(readSize))

        guard let text = String(data: data, encoding: .utf8) else { return nil }

        for line in text.components(separatedBy: "\n") {
            guard !line.isEmpty else { continue }
            do {
                guard let lineData = line.data(using: .utf8),
                      let obj = try JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      obj["type"] as? String == "user" else { continue }
                return extractText(from: obj)
            } catch {
                continue
            }
        }
        return nil
    }

    // MARK: - Tail parsing (messages, todos, subagents)

    private struct TailData {
        let lastUserPrompt: String?
        let lastAssistantMessage: String?
        let todos: [TodoItem]
        let subagents: [SubagentInfo]
        let permissionMode: String?
        let isConversationCompressed: Bool
    }

    private static func readTailData(fileHandle: FileHandle, fileSize: UInt64) -> TailData {
        let readSize = min(fileSize, tailReadSize)
        fileHandle.seek(toFileOffset: fileSize - readSize)
        let data = fileHandle.readDataToEndOfFile()

        guard let text = String(data: data, encoding: .utf8) else {
            return TailData(lastUserPrompt: nil, lastAssistantMessage: nil, todos: [], subagents: [], permissionMode: nil, isConversationCompressed: false)
        }

        var lines = text.components(separatedBy: "\n")
        if readSize < fileSize {
            lines.removeFirst()
        }

        var lastUserText: String?
        var lastAssistantText: String?
        var lastTodos: [TodoItem] = []
        var agentCalls: [String: (description: String, agentType: String)] = [:]
        var completedToolIds: Set<String> = []
        var lastPermissionMode: String?
        var foundCompactBoundary = false

        for line in lines.reversed() {
            guard !line.isEmpty else { continue }

            do {
                guard let lineData = line.data(using: .utf8),
                      let obj = try JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    continue
                }

                guard let type = obj["type"] as? String else { continue }

                switch type {
                case "user":
                    if lastUserText == nil {
                        lastUserText = extractText(from: obj)
                    }
                    if lastPermissionMode == nil, let mode = obj["permissionMode"] as? String {
                        lastPermissionMode = mode
                    }

                case "assistant":
                    if lastAssistantText == nil {
                        lastAssistantText = extractText(from: obj)
                    }
                    parseAssistantToolCalls(obj, todos: &lastTodos, agentCalls: &agentCalls)

                case "tool_result":
                    if let toolUseId = obj["tool_use_id"] as? String {
                        completedToolIds.insert(toolUseId)
                    }

                case "system":
                    if obj["subtype"] as? String == "compact_boundary" {
                        foundCompactBoundary = true
                    }

                default:
                    break
                }
            } catch {
                NSLog("[AgentIsland] ConversationLogParser: failed to parse line: %@", error.localizedDescription)
            }
        }

        let subagents = agentCalls.map { (id, info) in
            SubagentInfo(
                description: info.description,
                agentType: info.agentType,
                isComplete: completedToolIds.contains(id)
            )
        }

        return TailData(
            lastUserPrompt: lastUserText,
            lastAssistantMessage: lastAssistantText,
            todos: lastTodos,
            subagents: subagents,
            permissionMode: lastPermissionMode,
            isConversationCompressed: foundCompactBoundary
        )
    }

    private static func parseAssistantToolCalls(
        _ obj: [String: Any],
        todos: inout [TodoItem],
        agentCalls: inout [String: (description: String, agentType: String)]
    ) {
        guard let message = obj["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else { return }

        for item in content {
            guard item["type"] as? String == "tool_use",
                  let name = item["name"] as? String,
                  let input = item["input"] as? [String: Any] else { continue }

            if name == "TodoWrite" && todos.isEmpty {
                if let rawTodos = input["todos"] as? [[String: Any]] {
                    todos = rawTodos.compactMap { parseTodoItem($0) }
                }
            }

            if name == "Agent", let id = item["id"] as? String {
                let desc = input["description"] as? String ?? "Agent"
                let agentType = input["subagent_type"] as? String ?? "general"
                if agentCalls[id] == nil {
                    agentCalls[id] = (description: desc, agentType: agentType)
                }
            }
        }
    }

    private static func parseTodoItem(_ dict: [String: Any]) -> TodoItem? {
        guard let content = dict["content"] as? String,
              let statusStr = dict["status"] as? String,
              let status = TodoStatus(rawValue: statusStr),
              let activeForm = dict["activeForm"] as? String else { return nil }
        return TodoItem(content: content, status: status, activeForm: activeForm)
    }

    // MARK: - Helpers

    private static func jsonlPath(cwd: String, sessionId: String) -> String {
        let projectDir = cwd.replacingOccurrences(of: "/", with: "-")
        return NSHomeDirectory() + "/.claude/projects/" + projectDir + "/" + sessionId + ".jsonl"
    }

    static func extractText(from obj: [String: Any]) -> String? {
        guard let message = obj["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            return nil
        }
        for item in content {
            guard item["type"] as? String == "text",
                  let text = item["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            return String(cleaned.prefix(maxTextLength))
        }
        return nil
    }
}
