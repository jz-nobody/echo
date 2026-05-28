import Foundation

struct ClaudeSessionFile: Codable, Sendable, Equatable {
    let pid: Int
    let sessionId: String
    let cwd: String
    let startedAt: Int
    let version: String
    let kind: String
    let entrypoint: String
    let status: String?
    let updatedAt: Int?
}

enum SessionFileParser {
    static func parse(data: Data) -> ClaudeSessionFile? {
        try? JSONDecoder().decode(ClaudeSessionFile.self, from: data)
    }

    static func parseDirectory(at path: String) -> [ClaudeSessionFile] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        let allSessions = files
            .filter { $0.hasSuffix(".json") }
            .compactMap { filename -> ClaudeSessionFile? in
                let filePath = (path as NSString).appendingPathComponent(filename)
                guard let data = fm.contents(atPath: filePath) else { return nil }
                guard let session = parse(data: data) else { return nil }
                guard isProcessAlive(pid: session.pid) else { return nil }
                return session
            }
        return deduplicateByParent(allSessions)
    }

    private struct DeduplicationKey: Hashable {
        let parentPID: Int32
        let cwd: String
    }

    private static func deduplicateByParent(_ sessions: [ClaudeSessionFile]) -> [ClaudeSessionFile] {
        var vscodeByKey: [DeduplicationKey: [ClaudeSessionFile]] = [:]
        var others: [ClaudeSessionFile] = []

        for session in sessions {
            guard session.entrypoint == "claude-vscode" else {
                others.append(session)
                continue
            }
            let ppid = parentPID(of: Int32(session.pid)) ?? -1
            let key = DeduplicationKey(parentPID: ppid, cwd: session.cwd)
            vscodeByKey[key, default: []].append(session)
        }

        for (_, group) in vscodeByKey {
            if let best = group.max(by: { jsonlModTime($0) < jsonlModTime($1) }) {
                others.append(best)
            }
        }
        return others
    }

    private static func jsonlModTime(_ session: ClaudeSessionFile) -> Date {
        let path = ConversationLogParser.jsonlPath(cwd: session.cwd, sessionId: session.sessionId)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let modDate = attrs[.modificationDate] as? Date else {
            return .distantPast
        }
        return modDate
    }

    private static func parentPID(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 0 ? ppid : nil
    }

    static func toAgentSession(_ file: ClaudeSessionFile) -> AgentSession {
        let projectName = (file.cwd as NSString).lastPathComponent
        let startTime = Date(timeIntervalSince1970: Double(file.startedAt) / 1000.0)
        let status: SessionStatus
        if let fileStatus = file.status, fileStatus != "idle" {
            status = .executing
        } else {
            status = .idle
        }
        return AgentSession(
            id: file.sessionId,
            agentType: .claudeCode,
            title: projectName,
            status: status,
            startTime: startTime,
            lastUpdate: file.updatedAt.map { Date(timeIntervalSince1970: Double($0) / 1000.0) } ?? startTime,
            terminalInfo: TerminalInfo(appName: file.entrypoint, pid: Int32(file.pid), windowId: nil),
            currentToolCall: nil
        )
    }

    static func readStatus(pid: Int, directoryPath: String) -> String? {
        let filePath = (directoryPath as NSString).appendingPathComponent("\(pid).json")
        guard let data = FileManager.default.contents(atPath: filePath),
              let session = parse(data: data) else { return nil }
        return session.status
    }

    static func isProcessAlive(pid: Int) -> Bool {
        kill(Int32(pid), 0) == 0
    }
}
