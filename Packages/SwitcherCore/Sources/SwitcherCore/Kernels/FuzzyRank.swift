import Foundation

/// Subsequence matching over window title, app name and the two combined.
///
/// Search is the spine of the switcher, not a bolt-on: drill-down is fast when you
/// know roughly where a window is and slow when you don't, and real users reach for
/// typing more than for cycling.
public enum FuzzyRank {

    public struct Result: Sendable, Equatable {
        public let window: WindowEntry
        public let app: AppRef
        public let score: Int
        /// Indices into `window.title` that matched, for highlighting.
        public let titleMatches: [Int]
    }

    public static func rank(groups: [AppGroup], query: String, limit: Int = 100) -> [Result] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return [] }

        var scored: [(Result, Int)] = []
        for (appIndex, group) in groups.enumerated() {
            for (windowIndex, window) in group.windows.enumerated() {
                guard let match = best(needle: needle, window: window, app: group.app) else { continue }
                // Stable tiebreak on the MRU position the grouping already computed, so
                // equal-scoring matches never reshuffle between keystrokes.
                let order = appIndex * 1000 + windowIndex
                scored.append(
                    (Result(window: window, app: group.app, score: match.score, titleMatches: match.indices), order)
                )
            }
        }
        return scored
            .sorted { lhs, rhs in
                lhs.0.score == rhs.0.score ? lhs.1 < rhs.1 : lhs.0.score > rhs.0.score
            }
            .prefix(limit)
            .map(\.0)
    }

    private struct Match {
        let score: Int
        let indices: [Int]
    }

    private static func best(needle: String, window: WindowEntry, app: AppRef) -> Match? {
        let title = window.title.lowercased()
        let name = app.name.lowercased()

        if let inTitle = score(needle: needle, haystack: title) {
            return Match(score: inTitle.score + 200, indices: inTitle.indices)
        }
        if let inName = score(needle: needle, haystack: name) {
            // An app-name match is worth less than a title match, but should still beat
            // a tortured subsequence across the combined string.
            return Match(score: inName.score + 100, indices: [])
        }
        // "code api" should find the api-server window of VS Code.
        if let combined = score(needle: needle, haystack: "\(name) \(title)") {
            return Match(score: combined.score, indices: [])
        }
        return nil
    }

    /// Greedy subsequence match, rewarding matches that look deliberate: a prefix, a
    /// run of adjacent characters, or the start of a word.
    private static func score(needle: String, haystack: String) -> Match? {
        let hay = Array(haystack)
        let pins = Array(needle)
        var indices: [Int] = []
        var hayIndex = 0
        var total = 0
        var previousIndex = -2

        for pin in pins {
            var found = false
            while hayIndex < hay.count {
                defer { hayIndex += 1 }
                guard hay[hayIndex] == pin else { continue }
                if hayIndex == previousIndex + 1 { total += 15 }         // adjacency
                if hayIndex == 0 { total += 20 }                         // prefix
                else if !hay[hayIndex - 1].isLetter && !hay[hayIndex - 1].isNumber {
                    total += 10                                          // word boundary
                }
                total += 1
                indices.append(hayIndex)
                previousIndex = hayIndex
                found = true
                break
            }
            guard found else { return nil }
        }
        // Shorter haystacks are better matches for the same query.
        total += max(0, 30 - hay.count / 4)
        return Match(score: total, indices: indices)
    }
}
