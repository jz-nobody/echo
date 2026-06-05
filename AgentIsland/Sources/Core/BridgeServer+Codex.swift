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

        let query = """
            SELECT id, title, cwd, rollout_path, first_user_message,
                   created_at, updated_at, created_at_ms, updated_at_ms
            FROM threads
            WHERE archived = 0
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

            guard sessions[internalId] == nil else { continue }

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
    }

    // MARK: - Private

    private func ensureCodexSession(sessionId: String, cwd: String?) {
        let title = deriveCodexTitle(from: cwd)
        ensureSessionExists(id: sessionId, agentType: .codex, title: title, cwd: cwd)
    }

    private func updateCodexTerminalInfo(sessionId: String, clientPID: pid_t?) {
        guard sessions[sessionId]?.terminalInfo == nil, let pid = clientPID else { return }
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
