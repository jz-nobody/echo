import Foundation

struct WindowCandidate: Equatable, Sendable {
    let index: Int
    let title: String
    let isMinimized: Bool
    let isMain: Bool
}

enum WindowMatcher {
    static func selectTarget(
        windows: [WindowCandidate],
        sessionTitle: String
    ) -> Int? {
        var exactSegmentMatches: [WindowCandidate] = []
        var substringMatches: [WindowCandidate] = []

        for window in windows {
            if hasExactSegmentMatch(title: window.title, sessionTitle: sessionTitle) {
                exactSegmentMatches.append(window)
            } else if window.title.localizedCaseInsensitiveContains(sessionTitle) {
                substringMatches.append(window)
            }
        }

        let candidates: [WindowCandidate]
        if !exactSegmentMatches.isEmpty {
            candidates = exactSegmentMatches
        } else if !substringMatches.isEmpty {
            candidates = substringMatches
        } else {
            candidates = windows
        }

        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates[0].index }

        if let minimized = candidates.first(where: { $0.isMinimized }) {
            return minimized.index
        }

        if candidates.count > 1, let nonMain = candidates.first(where: { !$0.isMain }) {
            return nonMain.index
        }

        return candidates[0].index
    }

    static func indicestoReminimize(
        before: [WindowCandidate],
        targetIndex: Int?
    ) -> [Int] {
        before
            .filter { $0.isMinimized && $0.index != targetIndex }
            .map(\.index)
    }

    static func hasExactSegmentMatch(title: String, sessionTitle: String) -> Bool {
        let segments = title.components(separatedBy: " — ")
        return segments.contains { $0.caseInsensitiveCompare(sessionTitle) == .orderedSame }
    }
}
