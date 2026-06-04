import Testing
import Foundation
@testable import Vibrdrome

struct LRCLIBClientTests {

    @Test func parsesBasicSyncedLyrics() {
        let lines = LRCLIBClient.parseLRC("[00:12.34]Hello\n[00:15.00]World")
        #expect(lines.count == 2)
        #expect(lines[0].start == 12340)
        #expect(lines[0].value == "Hello")
        #expect(lines[1].start == 15000)
        #expect(lines[1].value == "World")
    }

    @Test func handlesFractionPrecision() {
        // .5 → 500ms, .05 → 50ms (centiseconds), .005 → 5ms (milliseconds)
        #expect(LRCLIBClient.parseLRC("[01:02.5]x").first?.start == 62500)
        #expect(LRCLIBClient.parseLRC("[01:02.05]x").first?.start == 62050)
        #expect(LRCLIBClient.parseLRC("[01:02.005]x").first?.start == 62005)
        #expect(LRCLIBClient.parseLRC("[00:00]x").first?.start == 0)
    }

    @Test func expandsMultipleTimestampsOnOneLine() {
        let lines = LRCLIBClient.parseLRC("[00:01.00][00:05.00]Repeat")
        #expect(lines.count == 2)
        #expect(lines.map(\.value) == ["Repeat", "Repeat"])
        #expect(lines[0].start == 1000)
        #expect(lines[1].start == 5000)
    }

    @Test func skipsMetadataAndUntimedLines() {
        let lrc = "[ar:Some Artist]\n[ti:Title]\n[offset:+250]\nplain line\n[00:03.00]Real"
        let lines = LRCLIBClient.parseLRC(lrc)
        #expect(lines.count == 1)
        #expect(lines[0].value == "Real")
        #expect(lines[0].start == 3000)
    }

    @Test func sortsByTimestamp() {
        let lines = LRCLIBClient.parseLRC("[00:09.00]Late\n[00:01.00]Early")
        #expect(lines.map(\.value) == ["Early", "Late"])
    }

    @Test func emptyForNonLRCText() {
        #expect(LRCLIBClient.parseLRC("just some\nplain lyrics\nno timestamps").isEmpty)
    }
}
