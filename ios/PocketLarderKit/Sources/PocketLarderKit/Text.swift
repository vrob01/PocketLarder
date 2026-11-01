import Foundation

public enum Limit {
    public static let name = 100, quantity = 32, note = 200
}

/// The server's `cleanText`: NFC, whitespace runs collapsed to one space, trimmed. Nil for a control character,
/// an empty result or more than `max` Unicode scalars. Scalars, because `Character` would swallow a mark or
/// U+200D attached to a space, and these two properties are the sets of Go's `unicode.IsSpace` and `IsControl`.
public func cleanText(_ s: String, max: Int) -> String? {
    var cleaned = String.UnicodeScalarView()
    var spaceDue = false
    for scalar in s.precomposedStringWithCanonicalMapping.unicodeScalars {
        if scalar.properties.isWhitespace {
            spaceDue = !cleaned.isEmpty
        } else if scalar.properties.generalCategory == .control {
            return nil
        } else {
            if spaceDue {
                cleaned.append(" ")
                spaceDue = false
            }
            cleaned.append(scalar)
        }
    }
    guard !cleaned.isEmpty, cleaned.count <= max else { return nil }
    return String(cleaned)
}

/// The uniqueness key for item names: the cleaned name, lowercased. `""` when nothing is left.
public func nameKey(_ s: String) -> String {
    cleanText(s, max: .max)?.lowercased() ?? ""
}

/// For search and sorting.
public func fold(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
}
