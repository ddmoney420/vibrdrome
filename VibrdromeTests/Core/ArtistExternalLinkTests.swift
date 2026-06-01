import Testing
import Foundation
@testable import Vibrdrome

struct ArtistExternalLinkTests {

    private func link(_ template: String) -> ArtistExternalLink {
        ArtistExternalLink(id: "test", label: "Test", urlTemplate: template)
    }

    // MARK: - #73 — query injection via permissive encoding

    @Test func artistNameWithQueryDelimitersIsEncoded() throws {
        // A malicious artist name must not inject extra query parameters.
        let l = link("https://example.com/search?q={artist}")
        let url = try #require(l.url(for: "Beatles&injected=value"))
        // The injected '&' / '=' must be percent-encoded, not passed through as
        // real query structure.
        #expect(!url.absoluteString.contains("&injected=value"))
        #expect(url.absoluteString.contains("Beatles%26injected%3Dvalue"))
    }

    @Test func artistNameEncodesReservedCharacters() throws {
        let l = link("https://example.com/?q={artist}")
        let url = try #require(l.url(for: "A B+C?D=E"))
        let s = url.absoluteString
        // Space, +, ?, = are all encoded; none leak as structural characters.
        #expect(s.contains("A%20B%2BC%3FD%3DE"))
    }

    @Test func unreservedCharactersArePreserved() throws {
        let l = link("https://example.com/?q={artist}")
        let url = try #require(l.url(for: "AC-DC_2.0~x"))
        #expect(url.absoluteString.hasSuffix("AC-DC_2.0~x"))
    }

    // MARK: - #74 — scheme allowlist

    @Test func httpAndHttpsSchemesAreAllowed() throws {
        #expect(link("http://example.com/{artist}").url(for: "x") != nil)
        #expect(link("https://example.com/{artist}").url(for: "x") != nil)
    }

    @Test func dangerousSchemesAreRejected() {
        let bad = [
            "javascript:alert(1)?a={artist}",
            "file:///etc/{artist}",
            "mailto:victim@example.com?subject={artist}",
            "myappscheme://open/{artist}"
        ]
        for template in bad {
            #expect(link(template).url(for: "x") == nil, "expected nil for \(template)")
        }
    }

    @Test func schemelessTemplateIsRejected() {
        #expect(link("example.com/{artist}").url(for: "x") == nil)
    }

    // MARK: - hasAllowedScheme (settings validator)

    @Test func hasAllowedSchemeMatchesOpenPolicy() {
        #expect(ArtistExternalLink.hasAllowedScheme("https://example.com/test"))
        #expect(ArtistExternalLink.hasAllowedScheme("HTTP://example.com/test"))
        #expect(!ArtistExternalLink.hasAllowedScheme("javascript:alert(1)"))
        #expect(!ArtistExternalLink.hasAllowedScheme("ftp://example.com"))
        #expect(!ArtistExternalLink.hasAllowedScheme("example.com/test"))
    }
}
