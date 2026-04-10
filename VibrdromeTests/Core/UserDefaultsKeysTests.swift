import Testing
import Foundation
@testable import Vibrdrome

/// Tests for UserDefaultsKeys centralized constants.
struct UserDefaultsKeysTests {

    // MARK: - All Keys Unique

    @Test func allKeysAreUnique() {
        let allKeys = allKeyValues()
        let uniqueKeys = Set(allKeys)
        #expect(allKeys.count == uniqueKeys.count,
                "All UserDefaultsKeys must be unique — found \(allKeys.count - uniqueKeys.count) duplicates")
    }

    @Test func totalKeyCount() {
        // 4 server + 4 audio + 4 EQ + 3 downloads + 2 streaming + 3 carplay
        // + 14 appearance + 1 discord + 2 listenbrainz + 4 lastfm + 1 adaptive + 2 library = 44
        #expect(allKeyValues().count == 44)
    }

    // MARK: - No Empty Keys

    @Test func noEmptyKeys() {
        for key in allKeyValues() {
            #expect(!key.isEmpty, "UserDefaultsKeys should not contain empty strings")
        }
    }

    // MARK: - Expected Key Values (regression)

    @Test func serverKeys() {
        #expect(UserDefaultsKeys.serverURL == "serverURL")
        #expect(UserDefaultsKeys.username == "username")
        #expect(UserDefaultsKeys.savedServers == "savedServers")
        #expect(UserDefaultsKeys.activeServerId == "activeServerId")
    }

    @Test func audioPlaybackKeys() {
        #expect(UserDefaultsKeys.gaplessPlayback == "gaplessPlayback")
        #expect(UserDefaultsKeys.crossfadeDuration == "crossfadeDuration")
        #expect(UserDefaultsKeys.replayGainMode == "replayGainMode")
        #expect(UserDefaultsKeys.scrobblingEnabled == "scrobblingEnabled")
    }

    @Test func eqKeys() {
        #expect(UserDefaultsKeys.eqEnabled == "eqEnabled")
        #expect(UserDefaultsKeys.eqCurrentPresetId == "eqCurrentPresetId")
        #expect(UserDefaultsKeys.eqCurrentGains == "eqCurrentGains")
        #expect(UserDefaultsKeys.customEQPresets == "customEQPresets")
    }

    @Test func downloadKeys() {
        #expect(UserDefaultsKeys.autoDownloadFavorites == "autoDownloadFavorites")
        #expect(UserDefaultsKeys.downloadOverCellular == "downloadOverCellular")
        #expect(UserDefaultsKeys.cacheLimitBytes == "cacheLimitBytes")
    }

    @Test func streamingKeys() {
        #expect(UserDefaultsKeys.wifiMaxBitRate == "wifiMaxBitRate")
        #expect(UserDefaultsKeys.cellularMaxBitRate == "cellularMaxBitRate")
    }

    @Test func carPlayKeys() {
        #expect(UserDefaultsKeys.carPlayShowRadio == "carPlayShowRadio")
        #expect(UserDefaultsKeys.carPlayShowGenres == "carPlayShowGenres")
        #expect(UserDefaultsKeys.carPlayRecentCount == "carPlayRecentCount")
    }

    @Test func appearanceKeys() {
        #expect(UserDefaultsKeys.appColorScheme == "appColorScheme")
        #expect(UserDefaultsKeys.accentColorTheme == "accentColorTheme")
        #expect(UserDefaultsKeys.largerText == "largerText")
        #expect(UserDefaultsKeys.textSize == "textSize")
        #expect(UserDefaultsKeys.autoSyncPlaylists == "autoSyncPlaylists")
        #expect(UserDefaultsKeys.showSearchTab == "showSearchTab")
        #expect(UserDefaultsKeys.showPlaylistsTab == "showPlaylistsTab")
        #expect(UserDefaultsKeys.showRadioTab == "showRadioTab")
        #expect(UserDefaultsKeys.boldText == "boldText")
        #expect(UserDefaultsKeys.reduceMotion == "reduceMotion")
        #expect(UserDefaultsKeys.disableVisualizer == "disableVisualizer")
        #expect(UserDefaultsKeys.visualizerWarningShown == "visualizerWarningShown")
        #expect(UserDefaultsKeys.showAlbumArtInLists == "showAlbumArtInLists")
        #expect(UserDefaultsKeys.visualizerPreset == "visualizerPreset")
    }

    @Test func discordKeys() {
        #expect(UserDefaultsKeys.discordRPCEnabled == "discordRPCEnabled")
    }

    @Test func listenBrainzKeys() {
        #expect(UserDefaultsKeys.listenBrainzEnabled == "listenBrainzEnabled")
        #expect(UserDefaultsKeys.listenBrainzToken == "listenBrainzToken")
    }

    @Test func lastFmKeys() {
        #expect(UserDefaultsKeys.lastFmEnabled == "lastFmEnabled")
        #expect(UserDefaultsKeys.lastFmApiKey == "lastFmApiKey")
        #expect(UserDefaultsKeys.lastFmSecret == "lastFmSecret")
        #expect(UserDefaultsKeys.lastFmSessionKey == "lastFmSessionKey")
    }

    @Test func adaptiveBitrateKeys() {
        #expect(UserDefaultsKeys.adaptiveBitrateEnabled == "adaptiveBitrateEnabled")
    }

    @Test func libraryLayoutKeys() {
        #expect(UserDefaultsKeys.libraryLayout == "libraryLayout")
        #expect(UserDefaultsKeys.activeMusicFolderId == "activeMusicFolderId")
    }

    // MARK: - Helpers

    private func allKeyValues() -> [String] {
        [
            // Server
            UserDefaultsKeys.serverURL,
            UserDefaultsKeys.username,
            UserDefaultsKeys.savedServers,
            UserDefaultsKeys.activeServerId,
            // Audio
            UserDefaultsKeys.gaplessPlayback,
            UserDefaultsKeys.crossfadeDuration,
            UserDefaultsKeys.replayGainMode,
            UserDefaultsKeys.scrobblingEnabled,
            // EQ
            UserDefaultsKeys.eqEnabled,
            UserDefaultsKeys.eqCurrentPresetId,
            UserDefaultsKeys.eqCurrentGains,
            UserDefaultsKeys.customEQPresets,
            // Downloads
            UserDefaultsKeys.autoDownloadFavorites,
            UserDefaultsKeys.downloadOverCellular,
            UserDefaultsKeys.cacheLimitBytes,
            // Streaming
            UserDefaultsKeys.wifiMaxBitRate,
            UserDefaultsKeys.cellularMaxBitRate,
            // CarPlay
            UserDefaultsKeys.carPlayShowRadio,
            UserDefaultsKeys.carPlayShowGenres,
            UserDefaultsKeys.carPlayRecentCount,
            // Appearance
            UserDefaultsKeys.appColorScheme,
            UserDefaultsKeys.accentColorTheme,
            UserDefaultsKeys.largerText,
            UserDefaultsKeys.textSize,
            UserDefaultsKeys.autoSyncPlaylists,
            UserDefaultsKeys.showSearchTab,
            UserDefaultsKeys.showPlaylistsTab,
            UserDefaultsKeys.showRadioTab,
            UserDefaultsKeys.boldText,
            UserDefaultsKeys.reduceMotion,
            UserDefaultsKeys.disableVisualizer,
            UserDefaultsKeys.visualizerWarningShown,
            UserDefaultsKeys.showAlbumArtInLists,
            UserDefaultsKeys.visualizerPreset,
            // Discord
            UserDefaultsKeys.discordRPCEnabled,
            // ListenBrainz
            UserDefaultsKeys.listenBrainzEnabled,
            UserDefaultsKeys.listenBrainzToken,
            // Last.fm
            UserDefaultsKeys.lastFmEnabled,
            UserDefaultsKeys.lastFmApiKey,
            UserDefaultsKeys.lastFmSecret,
            UserDefaultsKeys.lastFmSessionKey,
            // Adaptive Bitrate
            UserDefaultsKeys.adaptiveBitrateEnabled,
            // Library
            UserDefaultsKeys.libraryLayout,
            UserDefaultsKeys.activeMusicFolderId,
        ]
    }
}
