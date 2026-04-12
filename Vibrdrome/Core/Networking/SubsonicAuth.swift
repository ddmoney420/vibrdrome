import Foundation
import CryptoKit

struct SubsonicAuth: Sendable {
    let username: String
    let password: String
    let clientName = "vibrdrome"
    let apiVersion = "1.16.1"

    private func generateSalt(length: Int = 12) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }

    private func md5Hash(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    func authParameters() -> [URLQueryItem] {
        let salt = generateSalt()
        let token = md5Hash(password + salt)
        return [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: apiVersion),
            URLQueryItem(name: "c", value: clientName),
            URLQueryItem(name: "f", value: "json"),
        ]
    }
}
