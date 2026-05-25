import Foundation

enum ConversationLogParser {
    struct LastMessages: Sendable {
        let userPrompt: String?
        let assistantMessage: String?
    }

    enum LastMessageType: String, Sendable {
        case user
        case assistant
        case toolResult = "tool_result"
        case systemCompact = "system_compact"
        case system
        case unknown
    }

    struct ConversationSnapshot: Sendable {
        let sessionDescription: String?
        let lastUserPrompt: String?
        let lastAssistantMessage: String?
        let todos: [TodoItem]
        let subagents: [SubagentInfo]
        let permissionMode: String?
        let isConversationCompressed: Bool
        let lastMessageType: LastMessageType
        let lastAssistantHasToolUse: Bool
        let lastToolName: String?
        let currentToolCall: String?
        let isPostCompact: Bool
        let entriesSinceCompact: Int?
    }

    private static let headReadSize: UInt64 = 65536
    private static let tailReadSize: UInt64 = 262_144
    private static let maxTextLength = 200

    // MARK: - Public API

    static func snapshot(cwd: String, sessionId: String) -> ConversationSnapshot {
        let path = jsonlPath(cwd: cwd, sessionId: sessionId)
        return snapshot(atPath: path)
    }

    static func snapshot(atPath path: String) -> ConversationSnapshot {
        guard let fileHandle = FileHandle(forReadingAtPath: path) else {
            return ConversationSnapshot(sessionDescription: nil, lastUserPrompt: nil, lastAssistantMessage: nil, todos: [], subagents: [], permissionMode: nil, isConversationCompressed: false, lastMessageType: .unknown, lastAssistantHasToolUse: false, lastToolName: nil, currentToolCall: nil, isPostCompact: false, entriesSinceCompact: nil)
        }
        defer { fileHandle.closeFile() }

        let fileSize = fileHandle.seekToEndOfFile()
        guard fileSize > 0 else {
            return ConversationSnapshot(sessionDescription: nil, lastUserPrompt: nil, lastAssistantMessage: nil, todos: [], subagents: [], permissionMode: nil, isConversationCompressed: false, lastMessageType: .unknown, lastAssistantHasToolUse: false, lastToolName: nil, currentToolCall: nil, isPostCompact: false, entriesSinceCompact: nil)
        }

        let description = readSessionDescription(fileHandle: fileHandle, fileSize: fileSize)
        let tailData = readTailData(fileHandle: fileHandle, fileSize: fileSize)

        var todos = tailData.todos
        if todos.isEmpty && !tailData.isConversationCompressed {
            todos = findLastTodos(fileHandle: fileHandle, fileSize: fileSize, skipTailBytes: tailReadSize)
        }

        return ConversationSnapshot(
            sessionDescription: description,
            lastUserPrompt: tailData.lastUserPrompt,
            lastAssistantMessage: tailData.lastAssistantMessage,
            todos: todos,
            subagents: tailData.subagents,
            permissionMode: tailData.permissionMode,
            isConversationCompressed: tailData.isConversationCompressed,
            lastMessageType: tailData.lastMessageType,
            lastAssistantHasToolUse: tailData.lastAssistantHasToolUse,
            lastToolName: tailData.lastToolName,
            currentToolCall: tailData.currentToolCall,
            isPostCompact: tailData.isPostCompact,
            entriesSinceCompact: tailData.entriesSinceCompact
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
        let lastMessageType: LastMessageType
        let lastAssistantHasToolUse: Bool
        let lastToolName: String?
        let currentToolCall: String?
        let isPostCompact: Bool
        let entriesSinceCompact: Int?
    }

    private static func readTailData(fileHandle: FileHandle, fileSize: UInt64) -> TailData {
        let readSize = min(fileSize, tailReadSize)
        fileHandle.seek(toFileOffset: fileSize - readSize)
        let data = fileHandle.readDataToEndOfFile()

        guard let text = String(data: data, encoding: .utf8) else {
            return TailData(lastUserPrompt: nil, lastAssistantMessage: nil, todos: [], subagents: [], permissionMode: nil, isConversationCompressed: false, lastMessageType: .unknown, lastAssistantHasToolUse: false, lastToolName: nil, currentToolCall: nil, isPostCompact: false, entriesSinceCompact: nil)
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
        var detectedLastType: LastMessageType?
        var lastAssistantHasToolUse = false
        var lastToolName: String?
        var currentToolCall: String?
        var foundAssistantBeforeCompact = false
        var nonMetadataCount = 0
        var entriesSinceCompact: Int?

        let metadataTypes: Set<String> = [
            "attachment", "last-prompt", "ai-title",
            "queue-operation", "file-history-snapshot"
        ]

        for line in lines.reversed() {
            guard !line.isEmpty else { continue }

            do {
                guard let lineData = line.data(using: .utf8),
                      let obj = try JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    continue
                }

                guard let type = obj["type"] as? String else { continue }

                if !metadataTypes.contains(type) {
                    nonMetadataCount += 1
                }

                if detectedLastType == nil && !metadataTypes.contains(type) {
                    switch type {
                    case "user": detectedLastType = .user
                    case "assistant": detectedLastType = .assistant
                    case "tool_result": detectedLastType = .toolResult
                    case "system":
                        detectedLastType = obj["subtype"] as? String == "compact_boundary" ? .systemCompact : .system
                    default: detectedLastType = .unknown
                    }
                }

                switch type {
                case "user":
                    if lastUserText == nil {
                        lastUserText = extractText(from: obj)
                    }
                    if lastPermissionMode == nil, let mode = obj["permissionMode"] as? String {
                        lastPermissionMode = mode
                    }

                case "assistant":
                    if !foundCompactBoundary {
                        foundAssistantBeforeCompact = true
                    }
                    if lastAssistantText == nil {
                        lastAssistantText = extractText(from: obj)
                        if let message = obj["message"] as? [String: Any],
                           let content = message["content"] as? [[String: Any]] {
                            let toolUses = content.filter { $0["type"] as? String == "tool_use" }
                            lastAssistantHasToolUse = !toolUses.isEmpty
                            if let lastTool = toolUses.last, lastToolName == nil {
                                lastToolName = lastTool["name"] as? String
                                currentToolCall = buildToolCallSummary(
                                    name: lastTool["name"] as? String,
                                    input: lastTool["input"] as? [String: Any]
                                )
                            }
                        }
                    }
                    parseAssistantToolCalls(obj, todos: &lastTodos, agentCalls: &agentCalls)

                case "tool_result":
                    if let toolUseId = obj["tool_use_id"] as? String {
                        completedToolIds.insert(toolUseId)
                    }

                case "system":
                    if obj["subtype"] as? String == "compact_boundary" {
                        foundCompactBoundary = true
                        if entriesSinceCompact == nil {
                            entriesSinceCompact = nonMetadataCount - 1
                        }
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
                id: id,
                description: info.description,
                agentType: info.agentType,
                isComplete: completedToolIds.contains(id)
            )
        }

        let isPostCompact = foundCompactBoundary && !foundAssistantBeforeCompact

        return TailData(
            lastUserPrompt: lastUserText,
            lastAssistantMessage: lastAssistantText,
            todos: lastTodos,
            subagents: subagents,
            permissionMode: lastPermissionMode,
            isConversationCompressed: foundCompactBoundary,
            lastMessageType: detectedLastType ?? .unknown,
            lastAssistantHasToolUse: lastAssistantHasToolUse,
            lastToolName: lastToolName,
            currentToolCall: currentToolCall,
            isPostCompact: isPostCompact,
            entriesSinceCompact: entriesSinceCompact
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

    // MARK: - Extended TodoWrite scan

    private static let todoScanChunkSize: UInt64 = 1_048_576
    private static let todoScanMaxDepth: UInt64 = 8_388_608

    private static func findLastTodos(fileHandle: FileHandle, fileSize: UInt64, skipTailBytes: UInt64) -> [TodoItem] {
        let alreadyScanned = min(fileSize, skipTailBytes)
        let remaining = fileSize - alreadyScanned
        guard remaining > 0 else { return [] }

        var scannedBytes: UInt64 = 0
        while scannedBytes < min(remaining, todoScanMaxDepth) {
            let chunkEnd = remaining - scannedBytes
            let readSize = min(todoScanChunkSize, chunkEnd)
            let offset = chunkEnd - readSize

            fileHandle.seek(toFileOffset: offset)
            let data = fileHandle.readData(ofLength: Int(readSize))

            guard let text = String(data: data, encoding: .utf8) else { break }

            let lines = text.components(separatedBy: "\n")
            for line in lines.reversed() {
                guard !line.isEmpty, line.contains("\"TodoWrite\"") else { continue }
                guard let lineData = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      obj["type"] as? String == "assistant",
                      let message = obj["message"] as? [String: Any],
                      let content = message["content"] as? [[String: Any]] else { continue }

                for item in content {
                    guard item["type"] as? String == "tool_use",
                          item["name"] as? String == "TodoWrite",
                          let input = item["input"] as? [String: Any],
                          let rawTodos = input["todos"] as? [[String: Any]] else { continue }

                    let todos = rawTodos.compactMap { parseTodoItem($0) }
                    if !todos.isEmpty { return todos }
                }
            }

            scannedBytes += readSize
        }
        return []
    }

    // MARK: - Helpers

    static func jsonlPath(cwd: String, sessionId: String) -> String {
        let projectDir = cwd.replacingOccurrences(of: "/", with: "-")
        return NSHomeDirectory() + "/.claude/projects/" + projectDir + "/" + sessionId + ".jsonl"
    }

    static func fileSize(atPath path: String) -> UInt64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64 else { return 0 }
        return size
    }

    static func scanAllSubagents(atPath path: String, fromOffset: UInt64 = 0) -> [SubagentInfo] {
        guard let fileHandle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { fileHandle.closeFile() }

        let fileSize = fileHandle.seekToEndOfFile()
        guard fileSize > fromOffset else { return [] }

        fileHandle.seek(toFileOffset: fromOffset)
        let data = fileHandle.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        let lines = text.components(separatedBy: "\n")

        var agentCalls: [String: (description: String, agentType: String)] = [:]
        var completedToolIds: Set<String> = []

        for line in lines {
            guard !line.isEmpty else { continue }
            guard line.contains("\"Agent\"") || line.contains("\"tool_result\"") else { continue }

            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = obj["type"] as? String else { continue }

            if type == "assistant" {
                guard let message = obj["message"] as? [String: Any],
                      let content = message["content"] as? [[String: Any]] else { continue }
                for item in content {
                    guard item["type"] as? String == "tool_use",
                          item["name"] as? String == "Agent",
                          let id = item["id"] as? String,
                          let input = item["input"] as? [String: Any] else { continue }
                    let desc = input["description"] as? String ?? "Agent"
                    let agentType = input["subagent_type"] as? String ?? "general"
                    if agentCalls[id] == nil {
                        agentCalls[id] = (description: desc, agentType: agentType)
                    }
                }
            } else if type == "tool_result" {
                if let toolUseId = obj["tool_use_id"] as? String {
                    completedToolIds.insert(toolUseId)
                }
            }
        }

        return agentCalls.map { (id, info) in
            SubagentInfo(
                id: id,
                description: info.description,
                agentType: info.agentType,
                isComplete: completedToolIds.contains(id)
            )
        }
    }

    static func scanAllSubagents(cwd: String, sessionId: String, fromOffset: UInt64 = 0) -> [SubagentInfo] {
        let path = jsonlPath(cwd: cwd, sessionId: sessionId)
        return scanAllSubagents(atPath: path, fromOffset: fromOffset)
    }

    private static func buildToolCallSummary(name: String?, input: [String: Any]?) -> String? {
        guard let name else { return nil }
        guard let input else { return name }
        switch name {
        case "Bash":
            if let cmd = input["command"] as? String {
                let short = cmd.count > 60 ? String(cmd.prefix(57)) + "..." : cmd
                return "Bash \(short)"
            }
        case "Read", "Write", "Edit":
            if let path = input["file_path"] as? String {
                return "\(name) \((path as NSString).lastPathComponent)"
            }
        case "WebFetch":
            if let url = input["url"] as? String { return "WebFetch \(String(url.prefix(50)))" }
        case "WebSearch":
            if let q = input["query"] as? String { return "WebSearch \(String(q.prefix(50)))" }
        case "Grep":
            if let p = input["pattern"] as? String { return "Grep \(String(p.prefix(40)))" }
        case "Glob":
            if let p = input["pattern"] as? String { return "Glob \(String(p.prefix(40)))" }
        case "Agent":
            if let d = input["description"] as? String { return "Agent \(String(d.prefix(50)))" }
        case "TodoWrite":
            return "TodoWrite"
        case "NotebookEdit":
            if let p = input["notebook_path"] as? String {
                return "NotebookEdit \((p as NSString).lastPathComponent)"
            }
        default:
            break
        }
        return name
    }

    static func extractText(from obj: [String: Any]) -> String? {
        guard let message = obj["message"] as? [String: Any] else { return nil }
        let content = message["content"]

        if let text = content as? String {
            let cleaned = stripSystemTags(text)
            return cleaned.isEmpty ? nil : String(cleaned.prefix(maxTextLength))
        }

        if let items = content as? [[String: Any]] {
            for item in items {
                guard item["type"] as? String == "text",
                      let text = item["text"] as? String else {
                    continue
                }
                let cleaned = stripSystemTags(text)
                guard !cleaned.isEmpty else { continue }
                return String(cleaned.prefix(maxTextLength))
            }
        }

        return nil
    }

    private static func stripSystemTags(_ text: String) -> String {
        var result = text
        while let openRange = result.range(of: "<"),
              let tagNameEnd = result[openRange.upperBound...].rangeOfCharacter(from: CharacterSet(charactersIn: "> ")),
              let closeTag = result.range(of: "</", range: openRange.upperBound..<result.endIndex) {
            let tagName = String(result[openRange.upperBound..<tagNameEnd.lowerBound])
            let endMarker = "</\(tagName)>"
            if let endRange = result.range(of: endMarker, range: openRange.lowerBound..<result.endIndex) {
                result.removeSubrange(openRange.lowerBound..<endRange.upperBound)
            } else {
                break
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }
}
