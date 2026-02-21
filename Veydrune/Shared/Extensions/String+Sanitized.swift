import Foundation

extension String {
    var sanitizedFileName: String {
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return components(separatedBy: illegal).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
