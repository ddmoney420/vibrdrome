import Testing
import Foundation
@testable import Vibrdrome

struct BiographyCleanerTests {

    private func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test func stripsSimpleHTMLTags() {
        let input = "<p>Hello <b>world</b></p>"
        #expect(clean(input) == "Hello world")
    }

    @Test func stripsAnchorTags() {
        let input = "Check out <a href=\"https://example.com\">this link</a> for more."
        #expect(clean(input) == "Check out this link for more.")
    }

    @Test func handlesPlainText() {
        let input = "No HTML here"
        #expect(clean(input) == "No HTML here")
    }

    @Test func handlesEmptyString() {
        #expect(clean("") == "")
    }

    @Test func trimsWhitespace() {
        let input = "  \n  Hello  \n  "
        #expect(clean(input) == "Hello")
    }

    @Test func stripsNestedTags() {
        let input = "<div><p>Nested <em>content</em></p></div>"
        #expect(clean(input) == "Nested content")
    }

    @Test func stripsSelfClosingTags() {
        let input = "Line one<br/>Line two"
        #expect(clean(input) == "Line oneLine two")
    }

    @Test func handlesLastFmBio() {
        let input = """
        Radiohead are an English rock band from Oxfordshire. \
        <a href="https://www.last.fm/music/Radiohead">Read more on Last.fm</a>
        """
        let result = clean(input)
        #expect(result.contains("Radiohead are an English"))
        #expect(!result.contains("<a"))
        #expect(!result.contains("href"))
    }
}
