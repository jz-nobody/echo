import Foundation

struct QueuedConfirmation: Identifiable, Equatable {
    let confirmation: PendingConfirmation
    let session: AgentSession
    var id: String { confirmation.id }
}

@MainActor
@Observable
final class ConfirmationQueue {
    private(set) var items: [QueuedConfirmation] = []
    private(set) var currentIndex: Int = 0

    var currentItem: QueuedConfirmation? {
        items.indices.contains(currentIndex) ? items[currentIndex] : nil
    }

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    func update(from confirmations: [String: [PendingConfirmation]], sessions: [AgentSession]) {
        let sessionMap = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })

        var newItems: [QueuedConfirmation] = []
        for (sessionId, confs) in confirmations {
            guard let session = sessionMap[sessionId] else { continue }
            for conf in confs {
                newItems.append(QueuedConfirmation(confirmation: conf, session: session))
            }
        }

        newItems.sort { $0.confirmation.timestamp < $1.confirmation.timestamp }

        let previousId = currentItem?.id
        items = newItems

        if items.isEmpty {
            currentIndex = 0
            return
        }

        if let prevId = previousId,
           let idx = items.firstIndex(where: { $0.id == prevId }) {
            currentIndex = idx
        } else {
            currentIndex = min(currentIndex, items.count - 1)
        }
    }

    func advance() {
        if currentIndex + 1 < items.count {
            currentIndex += 1
        } else {
            items = []
            currentIndex = 0
        }
    }
}
