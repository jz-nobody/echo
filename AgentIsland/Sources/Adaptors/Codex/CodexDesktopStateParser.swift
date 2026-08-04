import Foundation

/// Reads Codex desktop metadata stored separately from the thread database.
enum CodexDesktopStateParser {

    /// `session_index.jsonl` is the source Codex uses for the user-visible
    /// sidebar name. Later records supersede earlier records for the same id.
    static func threadNames(atPath path: String) -> [String: String] {
        guard let data = FileManager.default.contents(atPath: path) else { return [:] }

        var result: [String: String] = [:]
        for line in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let threadId = object["id"] as? String,
                  let title = object["thread_name"] as? String else { continue }
            let trimmedId = threadId.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedId.isEmpty, !trimmedTitle.isEmpty else { continue }
            result[trimmedId] = trimmedTitle
        }
        return result
    }

    /// Descriptions are AI-generated task summaries. They are useful only as a
    /// fallback when a thread has no explicit sidebar name.
    static func threadDescriptions(atPath path: String) -> [String: String] {
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let atomState = root["electron-persisted-atom-state"] as? [String: Any],
              let descriptions = atomState["thread-descriptions-v1"] as? [String: Any] else {
            return [:]
        }

        var result: [String: String] = [:]
        for (threadId, value) in descriptions {
            guard let title = value as? String else { continue }
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                result[threadId] = trimmed
            }
        }
        return result
    }
}
