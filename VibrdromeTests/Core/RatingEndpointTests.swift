import Testing
import Foundation
@testable import Vibrdrome

struct RatingEndpointTests {

    private func findQueryItem(_ items: [URLQueryItem], name: String) -> String? {
        items.first(where: { $0.name == name })?.value
    }

    @Test func setRatingPath() {
        #expect(SubsonicEndpoint.setRating(id: "1", rating: 5).path == "/rest/setRating")
    }

    @Test func setRatingQueryItems() {
        let items = SubsonicEndpoint.setRating(id: "song123", rating: 4).queryItems
        #expect(findQueryItem(items, name: "id") == "song123")
        #expect(findQueryItem(items, name: "rating") == "4")
    }

    @Test func setRatingZero() {
        let items = SubsonicEndpoint.setRating(id: "song1", rating: 0).queryItems
        #expect(findQueryItem(items, name: "rating") == "0")
    }

    @Test func setRatingFive() {
        let items = SubsonicEndpoint.setRating(id: "song1", rating: 5).queryItems
        #expect(findQueryItem(items, name: "rating") == "5")
    }

    @Test func songModelHasUserRating() {
        // Verify Song can decode with userRating
        let json = """
        {
            "id": "1", "title": "Test", "isDir": false,
            "userRating": 3
        }
        """.data(using: .utf8)!
        let song = try? JSONDecoder().decode(Song.self, from: json)
        #expect(song?.userRating == 3)
    }

    @Test func songModelWithoutRating() {
        let json = """
        {
            "id": "1", "title": "Test", "isDir": false
        }
        """.data(using: .utf8)!
        let song = try? JSONDecoder().decode(Song.self, from: json)
        #expect(song?.userRating == nil)
    }
}
