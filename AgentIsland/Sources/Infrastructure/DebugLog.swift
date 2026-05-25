import Foundation

enum DebugLog {
    private static let logPath = "/tmp/agent-island-debug.log"
    private static let lock = NSLock()

    static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        lock.lock()
        defer { lock.unlock() }
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: Data(line.utf8))
        }
    }
}
