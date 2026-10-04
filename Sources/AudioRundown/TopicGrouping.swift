import Foundation

/// A deterministic fallback when the small model cannot return a valid chapter plan.
/// Find changes in vocabulary across neighboring notes; all cuts remain on saved times.
enum TopicGrouping {
    static let stopWords = Set("a an the and or but of to in on at for from with as is are was were be been being it its this that these those they them their he him his she her we our you your i my me speaker speakers conversation discusses discussed describes described mention mentions mentioned notes noted also about into over after before while who what which how where when there then than not no so very more some one two said says says people person had has have do does did can could would should will may just now".split(separator: " ").map(String.init))

    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
            .filter { $0.count > 2 && !stopWords.contains($0) })
    }

    static func boundaries(_ notes: [String], desiredCount: Int) -> [Range<Int>] {
        guard !notes.isEmpty else { return [] }
        let count = min(notes.count, max(1, desiredCount))
        let sets = notes.map(words)
        let minimum = max(1, notes.count / (count * 2))
        var candidates: [(Int, Double)] = []
        for index in 1..<notes.count {
            let left = sets[max(0, index - 2)..<index].reduce(into: Set<String>()) { $0.formUnion($1) }
            let right = sets[index..<min(notes.count, index + 2)].reduce(into: Set<String>()) { $0.formUnion($1) }
            let score = Double(left.intersection(right).count) / Double(max(1, left.union(right).count))
            candidates.append((index, score))
        }
        candidates.sort { left, right in
            if left.1 == right.1 { return left.0 < right.0 }
            return left.1 < right.1
        }
        var cuts = [0, notes.count]
        for (index, _) in candidates {
            if cuts.count >= count + 1 { break }
            if cuts.allSatisfy({ abs($0 - index) >= minimum }) { cuts.append(index) }
        }
        cuts.sort()
        return zip(cuts, cuts.dropFirst()).map { $0..<$1 }
    }
}
