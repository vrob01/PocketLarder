import Testing
@testable import PocketLarderKit

@Test func cleanTextMatchesServer() {
    #expect(cleanText("  Burrito \t spice ", max: 100) == "Burrito spice")
    #expect(cleanText("", max: 100) == nil)
    #expect(cleanText("   ", max: 100) == nil)
    #expect(cleanText("a\u{0}b", max: 100) == nil)
    #expect(cleanText("a\u{7F}b", max: 100) == nil)
    #expect(cleanText(String(repeating: "x", count: 101), max: 100) == nil)
    #expect(cleanText(String(repeating: "x", count: 100), max: 100) == String(repeating: "x", count: 100))
    #expect(cleanText("a\r\nb", max: 100) == "a b")
    #expect(cleanText("a\u{A0}b", max: 100) == "a b")
    #expect(cleanText("a\u{85}b", max: 100) == "a b")

    // Scalars, because `==` on strings ignores the difference between composed and decomposed text.
    #expect(cleanText("A\u{0308}pfel", max: 100)?.unicodeScalars.elementsEqual("\u{C4}pfel".unicodeScalars) == true)
    #expect(cleanText(String(repeating: "A\u{0308}", count: 50), max: 50) != nil)

    let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
    #expect(cleanText(family, max: 100)?.unicodeScalars.elementsEqual(family.unicodeScalars) == true)
    #expect(cleanText("a \u{200D}b", max: 100)?.unicodeScalars.elementsEqual("a \u{200D}b".unicodeScalars) == true)
}

@Test func nameKeyAndFold() {
    #expect(nameKey(" MILK ") == nameKey("milk"))
    #expect(nameKey("   ") == "")
    #expect(fold("Äpfel") == "apfel")
}
