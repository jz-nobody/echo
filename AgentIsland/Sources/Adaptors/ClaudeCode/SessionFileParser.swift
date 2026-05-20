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
        return files
            .filter { $0.hasSuffix(".json") }
            .compactMap { filename -> ClaudeSessionFile? in
                let filePath = (path as NSString).appendingPathComponent(filename)
                guard let data = fm.contents(atPath: filePath) else { return nil }
                guard let session = parse(data: data) else { return nil }
                guard isProcessAlive(pid: session.pid) else { return nil }
                return session
            }
    }

    static func toAgentSession(_ file: ClaudeSessionFile) -> AgentSession {
        let projectName = (file.cwd as NSString).lastPathComponent
        let startTime = Date(timeIntervalSince1970: Double(file.startedAt) / 1000.0)
        let status: SessionStatus = (file.status == "idle") ? .idle : .executing
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

    static func isProcessAlive(pid: Int) -> Bool {
        kill(Int32(pid), 0) == 0
    }
}
