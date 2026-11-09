import Foundation

/// How people (and Siri's speech recognition) say device names, versus how they are
/// spelled in the Hue app. Siri writes "Lightstrip" as "Light Strip" and people say
/// "Vitrine" for a plug named "Vitrinen" — voice commands must match both.
public enum SpokenNames {
    /// English words that appear glued together in Hue product and device names.
    static let englishParts: Set<String> = [
        "light", "lights", "strip", "lamp", "bulb", "play", "bar", "spot", "go", "bloom", "iris",
        "tube", "ceiling", "floor", "table", "desk", "wall", "star", "glow", "smart", "plug",
        "led", "tv", "bed", "side", "top", "under", "back", "night", "sun", "moon", "box", "sign",
    ]

    /// Other ways to say `name`, excluding any that would collide with `taken`
    /// (all other names in the home, compared case-insensitively).
    public static func variants(of name: String, avoiding taken: Set<String>) -> [String] {
        var candidates: [String] = []
        candidates += splitCompound(name).map { [$0] } ?? []
        candidates += joinCompound(name).map { [$0] } ?? []
        candidates += numberVariants(of: name)

        let blocked = Set(taken.map { $0.lowercased() }).union([name.lowercased()])
        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = candidate.lowercased()
            return !blocked.contains(key) && seen.insert(key).inserted
        }
    }

    /// "Lightstrip" → "Light Strip" when both halves are known English words.
    static func splitCompound(_ name: String) -> String? {
        guard !name.contains(" ") else { return nil }
        let lower = name.lowercased()
        for index in lower.indices.dropFirst(2) where lower.distance(from: index, to: lower.endIndex) >= 2 {
            let head = String(lower[..<index])
            let tail = String(lower[index...])
            if englishParts.contains(head), englishParts.contains(tail) {
                let original = Array(name)
                let split = head.count
                return String(original[..<split]) + " " + String(original[split...]).capitalizedFirst
            }
        }
        return nil
    }

    /// "Light Strip" → "Lightstrip", the reverse of `splitCompound`.
    static func joinCompound(_ name: String) -> String? {
        let words = name.split(separator: " ")
        guard words.count == 2,
              englishParts.contains(words[0].lowercased()),
              englishParts.contains(words[1].lowercased())
        else { return nil }
        return String(words[0]) + words[1].lowercased()
    }

    /// German singular for a plural last word: "Vitrinen" → "Vitrine". (The other way
    /// round rarely helps — nobody calls one ceiling lamp "Deckenlampen".)
    static func numberVariants(of name: String) -> [String] {
        guard SiriWords.isGerman else { return [] }
        var words = name.split(separator: " ").map(String.init)
        guard let last = words.last, last.count >= 5, last.lowercased().hasSuffix("en") else { return [] }
        words[words.count - 1] = String(last.dropLast())
        return [words.joined(separator: " ")]
    }

    // MARK: Matching

    /// Folds case, accents, spaces and hyphens: "Light-Strip" == "lightstrip".
    public static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Like `normalized`, but also ignores German plural endings: "vitrine" == "vitrinen".
    static func stem(_ text: String) -> String {
        var value = normalized(text)
        for suffix in ["en", "n", "e"] where value.count > 4 && value.hasSuffix(suffix) {
            value.removeLast(suffix.count)
            break
        }
        return value
    }

    /// Finds the item whose name best matches `spoken`: exactly, then ignoring spacing
    /// and accents, then ignoring singular/plural — each only if the match is unambiguous.
    public static func bestMatch<Item>(for spoken: String, in items: [Item], name: (Item) -> String) -> Item? {
        if let exact = items.first(where: { name($0).compare(spoken, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return exact
        }
        let target = normalized(spoken)
        let loose = items.filter { normalized(name($0)) == target }
        if loose.count == 1 { return loose[0] }
        let stemmed = items.filter { stem(name($0)) == stem(spoken) }
        return stemmed.count == 1 ? stemmed[0] : nil
    }
}

private extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
