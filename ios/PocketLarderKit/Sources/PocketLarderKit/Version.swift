import Foundation

// The compatibility setting. Change it only by the rules under "Versioning" in AGENTS.md.
public let minimumServerVersion = Version(0, 1, 0)
public let supportedServerMajor = 0

/// A semantic version's MAJOR.MINOR.PATCH, without a pre-release or build suffix.
public struct Version: Comparable, Sendable, CustomStringConvertible {
    public let major, minor, patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Exactly three parts separated by dots, each `0` or ASCII digits without a leading zero that fit in `Int`.
    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { part -> Int? in
            guard part.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }),
                  part == "0" || !part.hasPrefix("0") else { return nil }
            return Int(part)
        }
        guard parts.count == 3, numbers.count == 3 else { return nil }
        self.init(numbers[0], numbers[1], numbers[2])
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (a: Version, b: Version) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }
}

/// What the app makes of the server's answer to `GET /v1/version`.
public enum ServerCompatibility: Equatable, Sendable {
    case compatible(Version)
    case incompatible(Incompatibility)
    /// No outcome, so it never blocks. `nil` is a 2xx whose body isn't `{"version": "MAJOR.MINOR.PATCH"}`; otherwise
    /// `.offline` when nothing answered, or what any other status than 2xx and 404 gives elsewhere.
    case couldNotCheck(APIError?)
}

public enum Incompatibility: Equatable, Sendable {
    /// Below the minimum, or nil for a 404: a server from before the route.
    case serverTooOld(Version?)
    /// A newer major than this app supports.
    case appTooOld(Version)
}
