import Testing
import Foundation
@testable import Vibrdrome

struct LastFmEncodingTests {

    // MARK: - URL Encoding

    @Test func specialCharactersAreEncoded() {
        // Characters that must be percent-encoded in form-urlencoded bodies
        let special = "+@&=!#$%^*(){}[]|\\:\";<>?,/ "
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = special.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""

        // None of the special characters should survive encoding
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("@"))
        #expect(!encoded.contains("&"))
        #expect(!encoded.contains("="))
        #expect(!encoded.contains(" "))
        #expect(!encoded.contains("!"))
    }

    @Test func alphanumericsNotEncoded() {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let plain = "abcXYZ019"
        let encoded = plain.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        #expect(encoded == plain)
    }

    @Test func tildeAndHyphenNotEncoded() {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let safe = "a-b_c.d~e"
        let encoded = safe.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        #expect(encoded == safe)
    }

    @Test func passwordWithPlusSign() {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let password = "my+password"
        let encoded = password.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        #expect(encoded == "my%2Bpassword")
    }

    @Test func passwordWithAtSign() {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let password = "user@domain"
        let encoded = password.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        #expect(encoded == "user%40domain")
    }
}
