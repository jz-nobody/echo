import AppKit
import Foundation
import SQLite3

extension BridgeServer {

    var codexDbPath: String {
        guard let config = agentConfigs["codex"] else {
            return NSHomeDirectory() + "/.codex/state_5.sqlite"
        }
        return (config.hookSettingsPath as NSString)
            .deletingLastPathComponent + "/state_5.sqlite"
    }

    // MARK: - Hook Handlers

    func handleCodexPermissionRequest(
        message: HookMessage, sessionId: String,
        clientPID: pid_t?, clientID: UUID,
        respond: @escaping @Sendable (HookResponse) -> Void
    ) {
        ensureCodexSession(sessionId: sessionId, cwd: message.cwd)
        updateCodexTerminalInfo(sessionId: sessionId, clientPID: clientPID)
        recordActivity(sessionId: sessionId)
        handlePermissionRequest(
            message: message, sessionId: sessionId,
            clientID: clientID, respond: respond
        )
    }

    func handleCodexStatusHook(
        message: HookMessage, sessionId: String,
        clientPID: pid_t?,
        clientID: UUID = UUID(),
        respond: @escaping @Sendable (HookResponse) -> Void
    ) {
        ensureCodexSession(sessionId: sessionId, cwd: message.cwd)
        updateCodexTerminalInfo(sessionId: sessionId, clientPID: clientPID)
        recordActivity(sessionId: sessionId)

        if let path = message.transcriptPath, !path.isEmpty {
            transcriptPaths[sessionId] = path
        }

        switch message.type {
        case "UserPromptSubmit":
            if let prompt = message.prompt {
                let cleaned = stripSystemReminders(prompt)
                sessions[sessionId]?.lastUserPrompt = cleaned
                if sessions[sessionId]?.title == "Codex" {
                    sessions[sessionId]?.title = truncateTitle(cleaned)
                }
            }
            clearStaleInteraction(for: sessionId)
            applyEvent(.userPromptSubmit, sessionId: sessionId)

        case "PreToolUse":
            let toolName = message.toolName ?? "Unknown"
            let toolInput = message.toolInput ?? [:]
            if toolName == "request_user_input" {
                clearStaleInteraction(for: sessionId)
                if handleCodexRequestUserInput(
                    message: message, sessionId: sessionId,
                    clientID: clientID, respond: respond
                ) {
                    return
                }
            }
            sessions[sessionId]?.currentToolCall = summarizeToolInput(name: toolName, input: toolInput)
            if toolName == "TodoWrite" {
                sessions[sessionId]?.todos = parseTodos(from: toolInput)
            }
            if toolName == "Agent" {
                addSubagent(sessionId: sessionId, from: toolInput)
            }
            clearStaleInteraction(for: sessionId)
            applyEvent(.preToolUse(toolName: message.toolName), sessionId: sessionId)

        case "PostToolUse", "PostToolUseFailure":
            sessions[sessionId]?.currentToolCall = nil
            clearStaleInteraction(for: sessionId)
            applyEvent(.postToolUse, sessionId: sessionId)

        case "Stop":
            sessions[sessionId]?.currentToolCall = nil
            clearStaleInteraction(for: sessionId)
            applyEvent(.turnCompleted, sessionId: sessionId)

        case "StopFailure":
            sessions[sessionId]?.currentToolCall = nil
            clearStaleInteraction(for: sessionId)
            applyEvent(.stopFailure, sessionId: sessionId)

        case "SessionStart":
            applyEvent(.sessionStart, sessionId: sessionId)

        case "PreCompact":
            applyEvent(.preCompact, sessionId: sessionId)

        case "SubagentStart":
            applyEvent(.subagentStart, sessionId: sessionId)

        case "SubagentStop":
            completeLastSubagent(sessionId: sessionId)
            applyEvent(.subagentStop, sessionId: sessionId)

        default:
            respond(.empty)
            return
        }

        respond(.empty)
    }

    // MARK: - SQLite Discovery

    func discoverCodexSessions() {
        guard agentConfigs["codex"] != nil else { return }
        let dbPath = codexDbPath
        guard FileManager.default.fileExists(atPath: dbPath) else { return }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }

        // Exclude subagent threads: they are nested under their parent (see
        // discoverCodexSubagents) rather than shown as top-level sessions. This
        // also keeps LIMIT 50 from being consumed by 100+ subagent rows.
        let query = """
            SELECT id, title, cwd, rollout_path, first_user_message,
                   created_at, updated_at, created_at_ms, updated_at_ms
            FROM threads
            WHERE archived = 0 AND source NOT LIKE '{"subagent"%'
            ORDER BY COALESCE(updated_at_ms, updated_at * 1000) DESC
            LIMIT 50
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let now = Date()

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idPtr = sqlite3_column_text(stmt, 0) else { continue }
            let threadId = String(cString: idPtr)
            let internalId = internalSessionId(agentType: .codex, hookSessionId: threadId)

            let titleStr = sqlite3_column_text(stmt, 1).map(String.init(cString:)) ?? ""
            let cwdStr = sqlite3_column_text(stmt, 2).map(String.init(cString:)) ?? ""
            let rolloutStr = sqlite3_column_text(stmt, 3).map(String.init(cString:)) ?? ""
            let firstMsg = sqlite3_column_text(stmt, 4).map(String.init(cString:)) ?? ""

            let createdSec = sqlite3_column_int64(stmt, 5)
            let updatedSec = sqlite3_column_int64(stmt, 6)
            let createdMs = sqlite3_column_type(stmt, 7) != SQLITE_NULL ? sqlite3_column_int64(stmt, 7) : 0
            let updatedMs = sqlite3_column_type(stmt, 8) != SQLITE_NULL ? sqlite3_column_int64(stmt, 8) : 0

            let updatedDate: Date
            if updatedMs > 0 {
                updatedDate = Date(timeIntervalSince1970: TimeInterval(updatedMs) / 1000.0)
            } else {
                updatedDate = Date(timeIntervalSince1970: TimeInterval(updatedSec))
            }

            guard now.timeIntervalSince(updatedDate) < Self.sessionVisibilityTimeout else { continue }

            if !rolloutStr.isEmpty {
                transcriptPaths[internalId] = rolloutStr
            }

            var sessionTitle = titleStr
            if sessionTitle.isEmpty || sessionTitle == "New Session" {
                if !firstMsg.isEmpty {
                    sessionTitle = truncateTitle(firstMsg)
                } else {
                    sessionTitle = deriveCodexTitle(from: cwdStr)
                }
            } else {
                sessionTitle = truncateTitle(sessionTitle)
            }

            if var existing = sessions[internalId] {
                if updatedDate > existing.lastUpdate {
                    existing.title = sessionTitle
                    existing.lastUpdate = updatedDate
                    sessions[internalId] = existing
                }
                if updatedDate > (lastActivityDates[internalId] ?? .distantPast) {
                    lastActivityDates[internalId] = updatedDate
                }
                continue
            }

            let startDate: Date
            if createdMs > 0 {
                startDate = Date(timeIntervalSince1970: TimeInterval(createdMs) / 1000.0)
            } else {
                startDate = Date(timeIntervalSince1970: TimeInterval(createdSec))
            }

            sessions[internalId] = AgentSession(
                id: internalId, agentType: .codex, title: sessionTitle,
                status: .idle, startTime: startDate, lastUpdate: updatedDate,
                terminalInfo: nil, currentToolCall: nil
            )
            lastActivityDates[internalId] = updatedDate
        }

        enrichCodexUserPrompts()
        discoverCodexSubagents(db: db, now: now)
    }

    /// Fills in the latest user message for Codex sessions from their rollout log
    /// (SQLite discovery only knows the first message). Hooks, when present, still
    /// take priority — we never overwrite a non-empty prompt with an empty parse.
    private func enrichCodexUserPrompts() {
        for (id, session) in sessions where session.agentType == .codex {
            guard let path = transcriptPaths[id],
                  let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let size = (attrs[.size] as? NSNumber)?.uint64Value else { continue }
            // Reuse the cached prompt unless the rollout has grown (avoids re-scanning
            // large, unchanged transcripts every poll).
            if let cached = codexPromptCache[id], cached.size == size {
                sessions[id]?.lastUserPrompt = cached.prompt
                continue
            }
            if let prompt = CodexRolloutParser.lastUserPrompt(atPath: path), !prompt.isEmpty {
                let capped = String(prompt.prefix(200))
                codexPromptCache[id] = (size, capped)
                sessions[id]?.lastUserPrompt = capped
            }
        }
    }

    /// Reads recently-active subagent threads and nests them under their parent
    /// session's `subagents` list instead of surfacing them as top-level sessions.
    private func discoverCodexSubagents(db: OpaquePointer?, now: Date) {
        let cutoffMs = Int64((now.timeIntervalSince1970 - Self.codexActiveSubagentWindow) * 1000)
        let query = """
            SELECT id, source, title, agent_path, updated_at_ms, updated_at
            FROM threads
            WHERE archived = 0 AND source LIKE '{"subagent"%'
              AND COALESCE(updated_at_ms, updated_at * 1000) > ?
            ORDER BY COALESCE(updated_at_ms, updated_at * 1000) DESC
            LIMIT 200
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, cutoffMs)

        var rows: [(childId: String, parentThreadId: String, nickname: String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idPtr = sqlite3_column_text(stmt, 0) else { continue }
            let childId = String(cString: idPtr)
            let sourceStr = sqlite3_column_text(stmt, 1).map(String.init(cString:)) ?? ""
            let titleStr = sqlite3_column_text(stmt, 2).map(String.init(cString:)) ?? ""
            let agentPath = sqlite3_column_text(stmt, 3).map(String.init(cString:)) ?? ""

            guard let parsed = parseCodexSubagentSource(sourceStr) else { continue }
            let nickname = codexSubagentLabel(
                nickname: parsed.nickname, title: titleStr, agentPath: agentPath
            )
            rows.append((childId: childId, parentThreadId: parsed.parentThreadId, nickname: nickname))
        }

        // Only nest+hide a subagent when its parent is a currently-present session
        // (i.e. an active orchestration whose children are background workers).
        // A subagent whose parent is NOT shown — an orphan, a handoff/nested thread
        // the user is driving directly — must stay visible, never vanish. The hidden
        // set is transient (recomputed every poll), so a thread that stops being a
        // nested child reappears; we no longer stash ids in backgroundSessionIds
        // (which never clears and would hide such a session forever).
        var hidden: Set<String> = []
        var groups: [String: [SubagentInfo]] = [:]
        for row in rows {
            let parentId = internalSessionId(agentType: .codex, hookSessionId: row.parentThreadId)
            guard sessions[parentId] != nil else { continue }
            let childId = internalSessionId(agentType: .codex, hookSessionId: row.childId)
            hidden.insert(childId)
            groups[parentId, default: []].append(
                SubagentInfo(id: childId, description: row.nickname, agentType: "codex", isComplete: false)
            )
        }
        codexSubagentThreadIds = hidden

        // Reset parents that no longer have active subagents: clear the stale nested
        // list and drop the "running" elevation back to their real status.
        for id in codexNestedParents where groups[id] == nil {
            guard sessions[id]?.agentType == .codex else { continue }
            sessions[id]?.subagents = nil
            if sessions[id]?.status == .executing {
                sessions[id]?.status = sessionStates[id]?.status ?? .idle
            }
        }
        codexNestedParents = Set(groups.keys)

        for (parentInternalId, subs) in groups {
            sessions[parentInternalId]?.subagents = subs.isEmpty ? nil : subs
            // A parent that delegates its work to (hidden) subagents doesn't call
            // tools itself, so no hook marks it running and it looks idle. Reflect
            // "running" while it has active subagents so the orchestration is visible.
            if let st = sessions[parentInternalId]?.status, st == .idle || st == .completed {
                sessions[parentInternalId]?.status = .executing
            }
        }
    }

    /// Groups parsed subagent rows by parent internal session id. Pure function — no
    /// SQLite / actor state access, so it is directly unit-testable.
    func buildCodexSubagentGroups(
        rows: [(childId: String, parentThreadId: String, nickname: String)]
    ) -> [String: [SubagentInfo]] {
        var groups: [String: [SubagentInfo]] = [:]
        for row in rows {
            let parentInternalId = internalSessionId(agentType: .codex, hookSessionId: row.parentThreadId)
            let childInternalId = internalSessionId(agentType: .codex, hookSessionId: row.childId)
            let info = SubagentInfo(
                id: childInternalId, description: row.nickname,
                agentType: "codex", isComplete: false
            )
            groups[parentInternalId, default: []].append(info)
        }
        return groups
    }

    /// Parses a Codex `threads.source` value. Returns nil for non-subagent sources
    /// (plain strings like "vscode"/"automation").
    func parseCodexSubagentSource(_ source: String) -> (parentThreadId: String, nickname: String?)? {
        guard source.hasPrefix("{"), let data = source.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subagent = obj["subagent"] as? [String: Any],
              let spawn = subagent["thread_spawn"] as? [String: Any],
              let parent = spawn["parent_thread_id"] as? String, !parent.isEmpty else {
            return nil
        }
        let nickname = spawn["agent_nickname"] as? String
        return (parentThreadId: parent, nickname: nickname)
    }

    private func codexSubagentLabel(nickname: String?, title: String, agentPath: String) -> String {
        if let nickname, !nickname.isEmpty { return nickname }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty && trimmedTitle != "New Session" {
            return truncateTitle(trimmedTitle)
        }
        if !agentPath.isEmpty {
            let last = (agentPath as NSString).lastPathComponent
            if !last.isEmpty { return last }
        }
        return "Subagent"
    }

    // MARK: - Private

    private func ensureCodexSession(sessionId: String, cwd: String?) {
        guard !codexSubagentThreadIds.contains(sessionId) else { return }
        let title = deriveCodexTitle(from: cwd)
        ensureSessionExists(id: sessionId, agentType: .codex, title: title, cwd: cwd)
    }

    private func updateCodexTerminalInfo(sessionId: String, clientPID: pid_t?) {
        guard let pid = clientPID else { return }
        if agentProcessPIDs[sessionId] == nil {
            if let codexPID = ProcessAncestry.findAgentProcessPID(from: pid, matching: "codex") {
                agentProcessPIDs[sessionId] = codexPID
            }
        }
        guard sessions[sessionId]?.terminalInfo == nil else { return }
        guard let terminalPID = ProcessAncestry.findTerminalAppPID(of: pid) else { return }
        let app = NSWorkspace.shared.runningApplications.first {
            $0.processIdentifier == terminalPID
        }
        let appName = app?.localizedName ?? "Terminal"
        sessions[sessionId]?.terminalInfo = TerminalInfo(
            appName: appName, pid: terminalPID, windowId: nil
        )
    }

    private func deriveCodexTitle(from cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty, cwd != "/" else { return "Codex" }
        let lastComponent = (cwd as NSString).lastPathComponent
        if lastComponent.hasPrefix(".") || lastComponent.isEmpty { return "Codex" }
        return lastComponent
    }
}
