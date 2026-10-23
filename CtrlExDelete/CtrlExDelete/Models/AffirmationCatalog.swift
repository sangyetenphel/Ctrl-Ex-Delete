import Foundation

/// One sentence for the "Grow with Kindness" game (same ids as the backend).
struct Affirmation: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let text: String
    let theme: String
    let themeLabel: String
}

/// The curated affirmation catalog. Opening the game never waits for the
/// network: it uses the last catalog fetched from the server (cached on the
/// phone) or, failing that, the copy bundled with the app. A fetch only
/// refreshes the cache for next time; it never changes a game in progress.
enum AffirmationCatalog {
    private struct File: Codable {
        let language: String
        let affirmations: [Affirmation]
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private static var cacheURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "affirmations-cache.json")
    }

    /// Right now, from the phone: the cached catalog, else the bundled one.
    static func load() -> [Affirmation] {
        if let cacheURL, let data = try? Data(contentsOf: cacheURL),
           let cached = try? decoder.decode(File.self, from: data), cached.affirmations.count >= 3 {
            return cached.affirmations
        }
        return bundled()
    }

    static func bundled() -> [Affirmation] {
        guard let url = Bundle.main.url(forResource: "Affirmations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? decoder.decode(File.self, from: data) else { return [] }
        return file.affirmations
    }

    /// Fetches the active catalog and caches it for the next game. Quietly
    /// keeps the old copy if the server can't be reached.
    static func refresh() async {
        guard let response = try? await APIClient.shared.affirmations(),
              response.affirmations.count >= 3, let cacheURL else { return }
        let file = File(language: response.language, affirmations: response.affirmations)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        if let data = try? encoder.encode(file) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    // MARK: Choosing sentences

    /// Three different affirmations, from three different themes when possible.
    static func pickSession(from catalog: [Affirmation], count: Int = 3) -> [Affirmation] {
        var byTheme = Dictionary(grouping: catalog, by: \.theme)
        var picked: [Affirmation] = []
        for theme in byTheme.keys.shuffled() where picked.count < count {
            if let choice = byTheme[theme]?.randomElement() {
                picked.append(choice)
                byTheme[theme]?.removeAll { $0 == choice }
            }
        }
        // Fewer themes than needed: fill from the rest, never repeating.
        let rest = catalog.filter { !picked.contains($0) }.shuffled()
        picked += rest.prefix(count - picked.count)
        return picked
    }

    /// "Try another affirmation": a sentence not used yet this game, from the
    /// same theme if one is left (so the session keeps its variety).
    static func replacement(for current: Affirmation, in catalog: [Affirmation],
                            excluding used: Set<String>) -> Affirmation? {
        let fresh = catalog.filter { !used.contains($0.id) && $0.id != current.id }
        return fresh.filter { $0.theme == current.theme }.randomElement() ?? fresh.randomElement()
    }
}
