import Foundation

// Words and grouping for the Story screen, kept free of SwiftUI so
// DevTests/run.sh can test them on the Mac. Built only from the memories
// the app already loaded; nothing is invented.

enum StoryText {

    /// "9 memories collected" (counts the scrapbook memories).
    static func memoriesCollected(_ count: Int) -> String {
        "\(count) \(count == 1 ? "memory" : "memories") collected"
    }

    struct MonthGroup: Equatable {
        let title: String      // "November 2026"
        let ids: [Int]         // memory ids, in the order given (newest first)
    }

    /// Groups memories by the month and year of their local date
    /// ("YYYY-MM-DD"), newest month first, keeping each month's memories in
    /// the order given. Memories without a readable date go last, under
    /// "Earlier". Months with no memories don't appear.
    static func byMonth(_ memories: [(id: Int, localDate: String)]) -> [MonthGroup] {
        var keys: [String] = []                 // "2026-11", in first-seen order
        var idsByKey: [String: [Int]] = [:]
        var undated: [Int] = []
        for memory in memories {
            guard let key = monthKey(memory.localDate) else { undated.append(memory.id); continue }
            if idsByKey[key] == nil { keys.append(key) }
            idsByKey[key, default: []].append(memory.id)
        }
        var groups = keys.sorted(by: >).map { MonthGroup(title: monthTitle($0), ids: idsByKey[$0] ?? []) }
        if !undated.isEmpty { groups.append(MonthGroup(title: "Earlier", ids: undated)) }
        return groups
    }

    /// "2026-11-03" → "2026-11"; nil when it isn't a calendar day.
    private static func monthKey(_ localDate: String) -> String? {
        let parts = localDate.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, let month = Int(parts[1]), (1...12).contains(month),
              Int(parts[0]) != nil, Int(parts[2]) != nil else { return nil }
        return "\(parts[0])-\(parts[1])"
    }

    /// "2026-11" → "November 2026".
    private static func monthTitle(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard let year = Int(parts[0]), let month = Int(parts[1]) else { return key }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "\(formatter.standaloneMonthSymbols[month - 1]) \(year)"
    }
}
