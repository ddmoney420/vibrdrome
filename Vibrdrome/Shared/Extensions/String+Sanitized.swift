import Foundation

extension String {
    var sanitizedFileName: String {
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return components(separatedBy: illegal).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Genre name formatted for user display. Removes semicolons (a legacy ID3
    /// multi-value separator) and collapses the resulting whitespace, so a tag
    /// like "Hip Hop; Pop" renders as "Hip Hop Pop". The original string is
    /// preserved for server queries since Navidrome matches the stored value.
    var cleanedGenreDisplay: String {
        split(separator: ";", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
