import Testing
import Foundation
@testable import Vibrdrome

struct RadioCoverArtTests {

    // MARK: - radioCoverArtId

    @Test func noCoverArtReturnsNil() {
        let station = InternetRadioStation(
            id: "123", name: "Test", streamUrl: "http://stream.test",
            homePageUrl: nil, coverArt: nil
        )
        #expect(station.radioCoverArtId == nil)
    }

    @Test func correctFormatPassesThrough() {
        let station = InternetRadioStation(
            id: "123", name: "Test", streamUrl: "http://stream.test",
            homePageUrl: nil, coverArt: "ra-123"
        )
        #expect(station.radioCoverArtId == "ra-123")
    }

    @Test func brokenFormatGetsCorrected() {
        // Navidrome 0.61 bug #5293: returns raw filename instead of ra-{id}
        let station = InternetRadioStation(
            id: "456", name: "Test", streamUrl: "http://stream.test",
            homePageUrl: nil, coverArt: "ba5ae18f_station_logo.png"
        )
        #expect(station.radioCoverArtId == "ra-456")
    }

    @Test func emptyCoverArtStillReturnsWorkaround() {
        let station = InternetRadioStation(
            id: "789", name: "Test", streamUrl: "http://stream.test",
            homePageUrl: nil, coverArt: ""
        )
        // coverArt is non-nil (empty string), so workaround applies
        #expect(station.radioCoverArtId == "ra-789")
    }
}
