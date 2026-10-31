import Foundation

public struct Invite: Equatable, Sendable {
    public let server: URL
    public let code: String

    public init(server: URL, code: String) {
        self.server = server
        self.code = code
    }
}

private let inviteMarker = "pocketlarder://invite?"

/// Finds the first `pocketlarder://invite?…` token in `text`, which may sit inside other text.
public func parseInvite(_ text: String) -> Invite? {
    guard let token = text.split(whereSeparator: \.isWhitespace).first(where: { $0.contains(inviteMarker) }),
          let start = token.range(of: inviteMarker),
          let components = URLComponents(string: String(token[start.lowerBound...])),
          components.host == "invite",
          let serverText = components.queryItems?.first(where: { $0.name == "server" })?.value,
          let server = normalizeServer(serverText),
          let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
          !code.isEmpty
    else { return nil }
    return Invite(server: server, code: code)
}

/// `https://host[:port]`, or `http://` for localhost and 127.0.0.1 only. Nil for anything else.
public func normalizeServer(_ text: String) -> URL? {
    var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.contains("://") { text = "https://" + text }
    guard let parsed = URLComponents(string: text),
          let scheme = parsed.scheme?.lowercased(),
          let host = parsed.host?.lowercased(), !host.isEmpty,
          parsed.user == nil, parsed.password == nil,
          parsed.path.isEmpty || parsed.path == "/",
          parsed.query == nil, parsed.fragment == nil
    else { return nil }
    guard scheme == "https" || (scheme == "http" && (host == "localhost" || host == "127.0.0.1")) else { return nil }
    var result = URLComponents()
    result.scheme = scheme
    result.host = host
    result.port = parsed.port
    return result.url
}
