import Foundation

/// Follows a spoken affirmation word by word, from real speech-recognition
/// transcripts. No timing tricks: a word turns green only once a transcript
/// contains it, in sentence order.
///
/// - Capitalisation, punctuation, curly quotes and common contractions are
///   normalised ("doesn't" = "does not", "1" = "one").
/// - Words are matched in order, so a repeated word ("I can … I can") needs
///   each of its occurrences, and extra or restarted words are simply skipped.
/// - Every partial transcript is matched from scratch (from `start`), so a
///   revised transcript can't double-count; the result is a count, not an
///   accumulation.
nonisolated struct AffirmationMatcher: Equatable, Sendable {
    /// The sentence as shown, split into words (punctuation kept for display).
    let displayWords: [String]
    /// Normalised target tokens, and which displayed word each belongs to.
    let tokens: [String]
    let tokenWord: [Int]

    init(sentence: String) {
        displayWords = sentence.split(whereSeparator: \.isWhitespace).map(String.init)
        var tokens: [String] = [], owners: [Int] = []
        for (index, word) in displayWords.enumerated() {
            for token in Self.normalize(word) {
                tokens.append(token)
                owners.append(index)
            }
        }
        self.tokens = tokens
        tokenWord = owners
    }

    var tokenCount: Int { tokens.count }

    /// How many target tokens a transcript covers, continuing from `start`
    /// (tokens already matched in an earlier listening attempt).
    func matchedCount(in transcript: String, from start: Int = 0) -> Int {
        let heard = Self.normalize(transcript)
        var position = min(max(start, 0), tokens.count)
        var index = 0
        while index < heard.count, position < tokens.count {
            let target = tokens[position]
            if Self.same(heard[index], target) {
                position += 1
                index += 1
            } else if index + 1 < heard.count, heard[index] + heard[index + 1] == target {
                position += 1                     // "my self" for "myself"
                index += 2
            } else if position + 1 < tokens.count, target + tokens[position + 1] == heard[index] {
                position += 2                     // "cannot" for "can not"
                index += 1
            } else {
                index += 1                        // an extra or restarted word: skip it
            }
        }
        return position
    }

    /// Displayed words whose tokens are all matched (they turn green).
    func greenWords(matched: Int) -> Set<Int> {
        var green = Set<Int>()
        for word in displayWords.indices {
            let wordTokens = tokenWord.indices.filter { tokenWord[$0] == word }
            if let last = wordTokens.last, last < matched { green.insert(word) }
            if wordTokens.isEmpty, (tokenWord.firstIndex { $0 > word } ?? tokens.count) <= matched {
                green.insert(word)                // a word made only of punctuation
            }
        }
        return green
    }

    // MARK: Normalising

    static func normalize(_ text: String) -> [String] {
        let lowered = text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        var result: [String] = []
        for raw in lowered.split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "\u{2014}" || $0 == "\u{2013}" }) {
            let trimmed = String(raw).trimmingCharacters(in: CharacterSet.alphanumerics.union(["'"]).inverted)
                .trimmingCharacters(in: ["'"])
            guard !trimmed.isEmpty else { continue }
            if let expanded = contractions[trimmed] {
                result.append(contentsOf: expanded)
            } else if let word = numbers[trimmed] {
                result.append(word)
            } else {
                let cleaned = trimmed.filter { $0.isLetter || $0.isNumber }
                if !cleaned.isEmpty { result.append(cleaned == "okay" ? "ok" : cleaned) }
            }
        }
        return result
    }

    /// Exact, or one small slip in a longer word ("protect"/"protects").
    static func same(_ heard: String, _ target: String) -> Bool {
        if heard == target { return true }
        guard target.count >= 5, abs(heard.count - target.count) <= 1 else { return false }
        // (Short words must match exactly: "can"/"can't" differ in meaning.)
        return editDistance(heard, target) <= 1
    }

    /// Edits needed to turn one word into the other, where swapping two
    /// neighbouring letters counts as one ("gentel" for "gentle").
    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }

    private static let contractions: [String: [String]] = [
        "i'm": ["i", "am"], "i've": ["i", "have"], "i'll": ["i", "will"], "i'd": ["i", "would"],
        "can't": ["can", "not"], "cannot": ["can", "not"], "won't": ["will", "not"], "don't": ["do", "not"],
        "doesn't": ["does", "not"], "didn't": ["did", "not"], "isn't": ["is", "not"], "aren't": ["are", "not"],
        "wasn't": ["was", "not"], "shouldn't": ["should", "not"], "couldn't": ["could", "not"],
        "wouldn't": ["would", "not"], "haven't": ["have", "not"], "it's": ["it", "is"], "that's": ["that", "is"],
        "what's": ["what", "is"], "there's": ["there", "is"], "let's": ["let", "us"], "you're": ["you", "are"],
        "we're": ["we", "are"], "they're": ["they", "are"], "you'll": ["you", "will"], "you've": ["you", "have"],
    ]

    private static let numbers: [String: String] = [
        "1": "one", "2": "two", "3": "three", "4": "four", "5": "five",
        "6": "six", "7": "seven", "8": "eight", "9": "nine", "10": "ten",
    ]
}
