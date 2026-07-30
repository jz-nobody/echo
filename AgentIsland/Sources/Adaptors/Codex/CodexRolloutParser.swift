import Foundation

/// Parses a Codex rollout transcript (`~/.codex/sessions/.../rollout-*.jsonl`) to
/// extract the latest genuine user message. Codex threads discovered via SQLite
/// carry only `first_user_message`; the newest prompt lives in the rollout log.
enum CodexRolloutParser {

    private static let chunkSize: UInt64 = 262_144
    private static let maxScanDepth: UInt64 = 4_194_304   // cap backward scan at 4 MB

    /// Returns the most recent real user message, skipping Codex-injected context
    /// (environment blocks, "Files mentioned by the user" preambles, tag wrappers).
    /// Scans backward in chunks (large orchestration turns can push the last user
    /// message well past a single tail read), bounded by maxScanDepth.
    static func lastUserPrompt(atPath path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { handle.closeFile() }
        let fileSize = handle.seekToEndOfFile()
        guard fileSize > 0 else { return nil }

        var scanned: UInt64 = 0
        while scanned < min(fileSize, maxScanDepth) {
            let end = fileSize - scanned
            let readSize = min(chunkSize, end)
            let offset = end - readSize
            handle.seek(toFileOffset: offset)
            guard let text = String(data: handle.readData(ofLength: Int(readSize)), encoding: .utf8) else { break }

            for line in text.components(separatedBy: "\n").reversed() {
                guard !line.isEmpty,
                      line.contains("\"role\":\"user\"") || line.contains("\"role\": \"user\"") else { continue }
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      obj["type"] as? String == "response_item",
                      let payload = obj["payload"] as? [String: Any],
                      payload["type"] as? String == "message",
                      payload["role"] as? String == "user",
                      let content = payload["content"] as? [[String: Any]] else { continue }

                for item in content {
                    guard let type = item["type"] as? String,
                          type == "input_text" || type == "text",
                          let raw = item["text"] as? String else { continue }
                    if let cleaned = cleanUserText(raw) { return cleaned }
                }
            }
            scanned += readSize
        }
        return nil
    }

    /// Returns nil for injected/non-user content, otherwise the cleaned message.
    static func cleanUserText(_ raw: String) -> String? {
        let stripped = stripTags(raw)
        guard !stripped.isEmpty else { return nil }
        if stripped.hasPrefix("# Files mentioned by the user") { return nil }
        if stripped.hasPrefix("<environment_context") { return nil }
        return stripped
    }

    private static func stripTags(_ text: String) -> String {
        var result = text
        while let open = result.range(of: "<"),
              let nameEnd = result[open.upperBound...].rangeOfCharacter(from: CharacterSet(charactersIn: "> ")) {
            let tag = String(result[open.upperBound..<nameEnd.lowerBound])
            if let end = result.range(of: "</\(tag)>", range: open.lowerBound..<result.endIndex) {
                result.removeSubrange(open.lowerBound..<end.upperBound)
            } else {
                break
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }
}
