import Foundation
import Network
import PocketLarderKit
import Security
import Testing
@testable import PocketLarder

/// A fully qualified public name whose DNS answer is the loopback address. ATS skips IP addresses, single-label names
/// such as `localhost` and `.local` names, so a test connecting by one of those would pass even if ATS refused the
/// override for real servers.
private let host = "localtest.me"
/// Resolves to the loopback address too, as every name under `localtest.me` does, but the certificate doesn't cover it.
private let misnamed = "wrong.localtest.me"

/// Runs in the app, under its App Transport Security, on one transport: without a trusted host, with another host trusted,
/// with this one trusted, and without one again, which a connection the trusted session accepted must not serve. Then
/// with a trusted name that the certificate doesn't cover, which the check of the name still refuses.
@Test func trustedHostPassesATS() async throws {
    for name in [host, misnamed] {
        let addresses = try resolve(name)
        try #require(
            !addresses.isEmpty && addresses.allSatisfy { $0.hasPrefix("127.") || $0 == "::1" },
            "\(name) resolves to \(addresses), not to the loopback address, so the request can't reach this test's server"
        )
    }
    let server = try await HTTPSServer()
    defer { server.stop() }
    let url = try #require(URL(string: "https://\(host):\(server.port)"))
    let transport = URLSessionTransport()
    let client = APIClient(server: url, token: nil, transport: transport)

    await expectCertificateRefused(transport, url, "With no trusted host")
    transport.trust(host: "other.example.test")
    await expectCertificateRefused(transport, url, "With other.example.test trusted")
    transport.trust(host: host)
    #expect(await client.serverVersion() == .compatible(minimumServerVersion))
    transport.trust(host: nil)
    await expectCertificateRefused(transport, url, "With the trusted host cleared again")

    transport.trust(host: misnamed)
    let misnamedURL = try #require(URL(string: "https://\(misnamed):\(server.port)/v1/version"))
    do {
        let (_, response) = try await transport.send(URLRequest(url: misnamedURL))
        Issue.record("With \(misnamed) trusted, the certificate for \(host) passed, and the server answered \(response.statusCode)")
    } catch let refused as CertificateRefused {
        let message = failureText(.certificateRefused(reason: refused.reason), host: refused.host)
        print("With \(misnamed) trusted, the refusal reads: \(message)")
        #expect(refused.host == misnamed)
        // Both the system's description and its list of failed checks say "name" for this check.
        #expect(refused.reason.localizedCaseInsensitiveContains("name"), "The reason doesn't name the failed check: \(refused.reason)")
    } catch {
        Issue.record("With \(misnamed) trusted, the request failed with \(error), not with CertificateRefused")
    }

    // `SecPKCS12Import` keeps the identity in memory on iOS.
    for itemClass in [kSecClassIdentity, kSecClassCertificate, kSecClassKey] {
        #expect(SecItemCopyMatching([kSecClass as String: itemClass] as CFDictionary, nil) == errSecItemNotFound)
    }
}

/// Expects `GET /v1/version` to fail on the server's certificate: a TLS or certificate error, -1200 to -1206.
private func expectCertificateRefused(
    _ transport: URLSessionTransport, _ server: URL, _ when: String, sourceLocation: SourceLocation = #_sourceLocation
) async {
    do {
        let (_, response) = try await transport.send(URLRequest(url: server.appending(path: "/v1/version")))
        Issue.record("\(when), the self-signed server answered with HTTP status \(response.statusCode)", sourceLocation: sourceLocation)
    } catch let error as URLError {
        #expect(
            (-1206 ... -1200).contains(error.code.rawValue),
            "\(when), the request failed with \(error.code.rawValue), not with a TLS or certificate error: \(error)",
            sourceLocation: sourceLocation
        )
    } catch {
        Issue.record("\(when), the request failed with \(error), not with a URLError", sourceLocation: sourceLocation)
    }
}

private struct ResolveFailure: Error, CustomStringConvertible {
    let description: String
}

/// The numeric addresses `name` resolves to.
private func resolve(_ name: String) throws -> [String] {
    var hints = addrinfo()
    hints.ai_socktype = SOCK_STREAM
    var list: UnsafeMutablePointer<addrinfo>?
    let status = getaddrinfo(name, nil, &hints, &list)
    guard status == 0 else {
        throw ResolveFailure(description: "\(name) doesn't resolve: \(String(cString: gai_strerror(status)))")
    }
    defer { freeaddrinfo(list) }
    var addresses: [String] = []
    var entry = list
    while let current = entry {
        var text = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(current.pointee.ai_addr, current.pointee.ai_addrlen, &text, socklen_t(text.count), nil, 0, NI_NUMERICHOST) == 0 {
            addresses.append(text.withUnsafeBufferPointer { String(cString: $0.baseAddress!) })
        }
        entry = current.pointee.ai_next
    }
    return addresses
}

/// HTTPS on this process's loopback with the identity below. It answers every request as the server answers
/// `GET /v1/version`, and keeps each connection open, so that a later request could reuse it.
private final class HTTPSServer {
    let port: UInt16
    private let listener: NWListener

    init() async throws {
        let local = try #require(sec_identity_create(try identity()))
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, local)
        let parameters = NWParameters(tls: tls)
        parameters.requiredInterfaceType = .loopback
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            answer(connection, buffered: Data())
        }
        port = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case let .failed(error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: .global())
        }
        self.listener = listener
    }

    func stop() {
        listener.cancel()
    }
}

/// Answers each complete request in what has arrived, then waits for more on the same connection.
private func answer(_ connection: NWConnection, buffered: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
        var buffered = buffered + (data ?? Data())
        // A GET has no body, so each request ends with its empty line.
        while let end = buffered.range(of: Data("\r\n\r\n".utf8)) {
            buffered.removeSubrange(..<end.upperBound)
            let body = #"{"version":"\#(minimumServerVersion)"}"#
            let reply = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
            connection.send(content: Data(reply.utf8), completion: .idempotent)
        }
        if isComplete || error != nil {
            connection.cancel()
        } else {
            answer(connection, buffered: buffered)
        }
    }
}

/// The test-only identity of `localtest.me`, as PKCS #12 with the password "test": a self-signed certificate with the
/// name as its SAN, serverAuth, SHA-256 and a P-256 key, valid for 825 days as Apple's rules allow.
// shortcut: the certificate expires on 2029-02-16; then remake it and paste the second command's output here:
//   openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -sha256 -days 825 -nodes -keyout key.pem -out cert.pem -subj /CN=localtest.me -addext subjectAltName=DNS:localtest.me -addext extendedKeyUsage=serverAuth -addext keyUsage=critical,digitalSignature -addext basicConstraints=critical,CA:FALSE
//   openssl pkcs12 -export -inkey key.pem -in cert.pem -passout pass:test -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 | openssl base64
private let identityPKCS12 = """
    MIIDwgIBAzCCA4gGCSqGSIb3DQEHAaCCA3kEggN1MIIDcTCCAmcGCSqGSIb3DQEH
    BqCCAlgwggJUAgEAMIICTQYJKoZIhvcNAQcBMBwGCiqGSIb3DQEMAQMwDgQInCqA
    FLLzA0ICAggAgIICIEI4CHHlaKVGgfmZDOFaqO94n806v2duaO2aNrSm09fSkrq4
    XhmO3/PoKkKbgZtU2kCCxEW0sED05xCUtajvkgYPIboMYUabbHIAzigYHXcYZgUv
    qvbjYGy7ZSuz9VcH1uMRhEnPwnDKu2oKc+dCS1KnnapidGuVlbv5Atb9rZXreQUe
    sCCsosFcd0ipLuaJYq50UrvkuksmRVjXo7discHTTVI7QAeHo6vMNQhfoOOu9NOa
    niyLMzGB/yOTsD02Mutk3DXK20YM5qGrHja0A79u5LunW5PAz1FnkAiUDI8PLVzD
    4LVlC8IuGRaFwSORhcihwGHYwRurh+FXEebhH89OfKR2i0Dc8jQ+8MvAiY7PzS4s
    nNRU92f0mr8lY0jBJ1xNuKSlixbpHeIANlMZQEI6AljqB5DqH2vUbWuwuU4UCTMb
    DTlgDH0IBoCUtB9PIpWtu4hsDW6mnhNfbS7/7y07KeCAdqnHlah4F9rixJTX2W1U
    11YpwInSCQKWLT1gSy7/wRDdrRWxkacj6GGzR4DEPhvnIr0TuxXb0qb9O5dDUDfC
    IY4yq38ZWR6eAl6vbrdgpvftkxzbNPuUriBjDcp7H6BT3iKqsOd88vEICuT9pFKh
    pQGdOpB9x7gFf+MYlgiWg4cjdeOjkzt0ys+XfKKPzzyNGDnDGTVG0cva8he5ZA88
    ABA1HofrRs/ZSpY5/oH7DJBs8XK28aiJlgSXlXwwggECBgkqhkiG9w0BBwGggfQE
    gfEwge4wgesGCyqGSIb3DQEMCgECoIG0MIGxMBwGCiqGSIb3DQEMAQMwDgQIBEpk
    N9XZuB4CAggABIGQx67vAKZaI7Ro9520yTOAMmt87Uvx7kxbrx/fHJnT39SL500Z
    IW7dFUmeVzlCqswsbjLEtu16KF1wsk9HSQZebrEK5xK5AErIZCZmqyLI3apBq44I
    0QG+RaCryE1qvxd9r2wlFKdMvEAJm2ZbmAhQJL1dG/hsIl6Z4uE2Ncbm1ZuVVGJ2
    IRN+WOv5UYBN3JJhMSUwIwYJKoZIhvcNAQkVMRYEFI7Vzt5wjXa3E+Cood9XTWkF
    mu9MMDEwITAJBgUrDgMCGgUABBS3RCsjjqeEbDfHTVaXiMm4UE9r3wQIjnQV/FCq
    e2ICAggA
    """

private func identity() throws -> SecIdentity {
    let data = try #require(Data(base64Encoded: identityPKCS12, options: .ignoreUnknownCharacters))
    var items: CFArray?
    let status = SecPKCS12Import(data as CFData, [kSecImportExportPassphrase as String: "test"] as CFDictionary, &items)
    try #require(status == errSecSuccess, "SecPKCS12Import failed with OSStatus \(status)")
    let first = try #require((items as? [[String: Any]])?.first)
    return try #require(first[kSecImportItemIdentity as String]) as! SecIdentity
}
