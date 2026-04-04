import Testing
import Foundation
@testable import Vibrdrome

/// Tests for the isLocalAddress logic used in ServerConfigView HTTP warning
struct LocalAddressTests {

    private func isLocal(_ urlString: String) -> Bool {
        guard let parsed = URL(string: urlString), let host = parsed.host else { return false }
        if host == "localhost" || host == "127.0.0.1" || host == "::1"
            || host.hasSuffix(".local") { return true }
        if host.hasPrefix("10.") || host.hasPrefix("192.168.")
            || host.hasPrefix("169.254.") { return true }
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]),
               (16...31).contains(second) { return true }
        }
        return false
    }

    // MARK: - Local addresses

    @Test func localhost() { #expect(isLocal("http://localhost:4533")) }
    @Test func loopbackIPv4() { #expect(isLocal("http://127.0.0.1:4533")) }
    @Test func loopbackIPv6() { #expect(isLocal("http://[::1]:4533")) }
    @Test func localDomain() { #expect(isLocal("http://myserver.local:4533")) }
    @Test func tenNetwork() { #expect(isLocal("http://10.0.1.3:4533")) }
    @Test func privateNetwork192() { #expect(isLocal("http://192.168.1.1:4533")) }
    @Test func linkLocal() { #expect(isLocal("http://169.254.1.1:4533")) }

    // RFC 1918: 172.16-31.x.x
    @Test func private172_16() { #expect(isLocal("http://172.16.0.1:4533")) }
    @Test func private172_24() { #expect(isLocal("http://172.24.5.10:4533")) }
    @Test func private172_31() { #expect(isLocal("http://172.31.255.255:4533")) }

    // MARK: - Non-local addresses

    @Test func publicIP() { #expect(!isLocal("http://73.95.255.208:4533")) }
    @Test func duckDNS() { #expect(!isLocal("http://example.duckdns.org:4533")) }
    @Test func httpsPublic() { #expect(!isLocal("https://music.example.com")) }
    @Test func private172_15() { #expect(!isLocal("http://172.15.0.1:4533")) }
    @Test func private172_32() { #expect(!isLocal("http://172.32.0.1:4533")) }
    @Test func publicDomain() { #expect(!isLocal("http://navidrome.io")) }
}
