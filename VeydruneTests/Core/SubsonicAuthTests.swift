import Testing
import Foundation
@testable import Veydrune

struct SubsonicAuthTests {

    @Test func authParametersContainsRequiredKeys() {
        let auth = SubsonicAuth(username: "testuser", password: "testpass")
        let params = auth.authParameters()
        let names = params.map(\.name)

        #expect(names.contains("u"))
        #expect(names.contains("t"))
        #expect(names.contains("s"))
        #expect(names.contains("v"))
        #expect(names.contains("c"))
        #expect(names.contains("f"))
    }

    @Test func authParametersUsername() {
        let auth = SubsonicAuth(username: "alice", password: "secret")
        let params = auth.authParameters()
        let username = params.first(where: { $0.name == "u" })?.value

        #expect(username == "alice")
    }

    @Test func authParametersFormat() {
        let auth = SubsonicAuth(username: "user", password: "pass")
        let params = auth.authParameters()
        let format = params.first(where: { $0.name == "f" })?.value

        #expect(format == "json")
    }

    @Test func authParametersClientName() {
        let auth = SubsonicAuth(username: "user", password: "pass")
        let params = auth.authParameters()
        let client = params.first(where: { $0.name == "c" })?.value

        #expect(client == "veydrune")
    }

    @Test func authParametersAPIVersion() {
        let auth = SubsonicAuth(username: "user", password: "pass")
        let params = auth.authParameters()
        let version = params.first(where: { $0.name == "v" })?.value

        #expect(version == "1.16.1")
    }

    @Test func tokenIsMD5Format() {
        let auth = SubsonicAuth(username: "user", password: "pass")
        let params = auth.authParameters()
        let token = params.first(where: { $0.name == "t" })?.value

        // MD5 produces 32 hex characters
        #expect(token != nil)
        #expect(token!.count == 32)
        #expect(token!.allSatisfy { $0.isHexDigit })
    }

    @Test func saltIsRandomized() {
        let auth = SubsonicAuth(username: "user", password: "pass")
        let params1 = auth.authParameters()
        let params2 = auth.authParameters()
        let salt1 = params1.first(where: { $0.name == "s" })?.value
        let salt2 = params2.first(where: { $0.name == "s" })?.value

        // Salts should differ between calls (vanishingly unlikely to collide)
        #expect(salt1 != salt2)
    }

    @Test func saltIsAlphanumeric() {
        let auth = SubsonicAuth(username: "user", password: "pass")
        let params = auth.authParameters()
        let salt = params.first(where: { $0.name == "s" })?.value

        #expect(salt != nil)
        #expect(salt!.allSatisfy { $0.isLetter || $0.isNumber })
    }

    @Test func tokenDiffersWithDifferentPasswords() {
        let auth1 = SubsonicAuth(username: "user", password: "password1")
        let auth2 = SubsonicAuth(username: "user", password: "password2")
        let token1 = auth1.authParameters().first(where: { $0.name == "t" })?.value
        let token2 = auth2.authParameters().first(where: { $0.name == "t" })?.value

        // Different passwords + different salts → different tokens
        #expect(token1 != token2)
    }

    @Test func passwordNeverInParameters() {
        let password = "supersecretpassword123"
        let auth = SubsonicAuth(username: "user", password: password)
        let params = auth.authParameters()

        for param in params {
            #expect(param.value != password, "Password should never appear as a parameter value")
        }
    }
}
