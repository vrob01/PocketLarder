import Testing
@testable import PocketLarderKit

@Test func versionParsing() {
    #expect(Version("0.1.0") == Version(0, 1, 0))
    #expect(Version("1.2.3") == Version(1, 2, 3))
    #expect(Version("10.20.30") == Version(10, 20, 30))
    #expect(Version("10.20.30")?.description == "10.20.30")
    for text in ["0.1", "0.1.0.0", "v0.1.0", "0.1.0-rc1", "0.1.0+1", "+1.0.0", "-1.0.0", "01.0.0", " 0.1.0", "a.b.c", "", "1..0",
                 "99999999999999999999.0.0"] {
        #expect(Version(text) == nil, "\(text) parsed")
    }
}

@Test func versionComparison() {
    #expect(Version(0, 1, 0) < Version(0, 2, 0))
    #expect(Version(0, 1, 0) < Version(0, 1, 1))
    #expect(Version(0, 9, 9) < Version(1, 0, 0))
    #expect(Version(0, 9, 0) < Version(0, 10, 0))
    #expect(Version("0.10.0")! > Version("0.9.0")!)
    #expect(!(Version(0, 1, 0) < Version(0, 1, 0)))
}
