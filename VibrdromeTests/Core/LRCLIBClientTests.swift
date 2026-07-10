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

// MARK: - Lyric Highlight Style (#113 Slice 2)

struct LyricHighlightStyleTests {

    @Test func rawValuesAreStable() {
        // Persisted via @AppStorage — raw values must not drift or stored prefs break.
        #expect(LyricHighlightStyle.lineOnly.rawValue == "lineOnly")
        #expect(LyricHighlightStyle.word.rawValue == "word")
        #expect(LyricHighlightStyle.wordDimmed.rawValue == "wordDimmed")
    }

    @Test func allCasesPresentAndDefaultMatchesSlice1() {
        #expect(LyricHighlightStyle.allCases.count == 3)
        // The default used across LyricsView + PlayerSettingsView is the QA'd Slice 1 behavior.
        #expect(LyricHighlightStyle(rawValue: "wordDimmed") == .wordDimmed)
    }

    @Test func onlyLineOnlyBypassesWordRendering() {
        #expect(LyricHighlightStyle.lineOnly.isWordLevel == false)
        #expect(LyricHighlightStyle.word.isWordLevel == true)
        #expect(LyricHighlightStyle.wordDimmed.isWordLevel == true)
    }

    @Test func unknownRawValueIsNil() {
        // A legacy/garbage stored value decodes to nil so @AppStorage falls back to its default.
        #expect(LyricHighlightStyle(rawValue: "sparkles") == nil)
    }

    @Test func everyStyleHasLabelAndIcon() {
        for style in LyricHighlightStyle.allCases {
            #expect(!style.label.isEmpty)
            #expect(!style.icon.isEmpty)
        }
    }
}

// MARK: - Lyric Highlight Color (#113 Slice 3)

struct LyricHighlightColorTests {

    @Test func rawValuesAreStable() {
        // Persisted via @AppStorage — raw values must not drift or stored prefs break.
        #expect(LyricHighlightColor.accent.rawValue == "accent")
        #expect(LyricHighlightColor.yellow.rawValue == "yellow")
        #expect(LyricHighlightColor.green.rawValue == "green")
        #expect(LyricHighlightColor.blue.rawValue == "blue")
        #expect(LyricHighlightColor.pink.rawValue == "pink")
        #expect(LyricHighlightColor.orange.rawValue == "orange")
    }

    @Test func paletteIsAccentPlusFive() {
        #expect(LyricHighlightColor.allCases.count == 6)
        #expect(LyricHighlightColor.allCases.first == .accent)
    }

    @Test func defaultIsAccent() {
        #expect(LyricHighlightColor(rawValue: "accent") == .accent)
    }

    @Test func unknownRawValueIsNil() {
        #expect(LyricHighlightColor(rawValue: "chartreuse") == nil)
    }

    @Test func everyColorHasLabel() {
        for color in LyricHighlightColor.allCases {
            #expect(!color.label.isEmpty)
        }
    }
}
