import Testing
import Foundation
@testable import Vibrdrome

@MainActor
struct SubsonicClientWebPTests {

    private func makeClient(serverVersion: String?) -> SubsonicClient {
        let client = SubsonicClient(
            baseURL: URL(string: "https://example.com")!,
            username: "user",
            password: "pass"
        )
        if let v = serverVersion {
            client.setServerVersionForTesting(v)
        }
        return client
    }

    @Test func supportsWebP_nilVersion_returnsFalse() {
        let client = makeClient(serverVersion: nil)
        #expect(client.supportsWebP == false)
    }

    @Test func supportsWebP_below049_returnsFalse() {
        for version in ["0.48.0", "0.48.9", "0.47.0", "0.1.0"] {
            let client = makeClient(serverVersion: version)
            #expect(client.supportsWebP == false, "Expected false for \(version)")
        }
    }

    @Test func supportsWebP_exactly049_returnsTrue() {
        let client = makeClient(serverVersion: "0.49.0")
        #expect(client.supportsWebP == true)
    }

    @Test func supportsWebP_above049_returnsTrue() {
        for version in ["0.49.1", "0.50.0", "0.52.5", "1.0.0"] {
            let client = makeClient(serverVersion: version)
            #expect(client.supportsWebP == true, "Expected true for \(version)")
        }
    }

    @Test func supportsWebP_malformedVersion_returnsFalse() {
        for version in ["", "notaversion", "0", "0."] {
            let client = makeClient(serverVersion: version)
            #expect(client.supportsWebP == false, "Expected false for malformed '\(version)'")
        }
    }

    @Test func coverArtURL_withWebP_containsFormatParam() {
        let client = makeClient(serverVersion: "0.52.5")
        let url = client.coverArtURL(id: "abc", size: 300)
        #expect(url.absoluteString.contains("format=webp"))
    }

    @Test func coverArtURL_withoutWebP_omitsFormatParam() {
        let client = makeClient(serverVersion: "0.48.0")
        let url = client.coverArtURL(id: "abc", size: 300)
        #expect(!url.absoluteString.contains("format=webp"))
    }

    @Test func coverArtURL_nilVersion_omitsFormatParam() {
        let client = makeClient(serverVersion: nil)
        let url = client.coverArtURL(id: "abc", size: 300)
        #expect(!url.absoluteString.contains("format=webp"))
    }
}
