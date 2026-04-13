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
        // 4 server + 5 audio + 4 EQ + 3 downloads + 2 streaming + 3 carplay
        // + 14 appearance + 6 toolbar + 1 discord + 2 listenbrainz + 5 lastfm
        // + 1 adaptive + 8 player behavior + 3 appearance ext
        // + 8 tab bar ext + 2 library = 71
        #expect(allKeyValues().count == 71)
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
        #expect(UserDefaultsKeys.lastFmUsername == "lastFmUsername")
    }

    @Test func adaptiveBitrateKeys() {
        #expect(UserDefaultsKeys.adaptiveBitrateEnabled == "adaptiveBitrateEnabled")
    }

    @Test func nowPlayingToolbarKeys() {
        #expect(UserDefaultsKeys.showVisualizerInToolbar == "showVisualizerInToolbar")
        #expect(UserDefaultsKeys.showEQInToolbar == "showEQInToolbar")
        #expect(UserDefaultsKeys.showAirPlayInToolbar == "showAirPlayInToolbar")
        #expect(UserDefaultsKeys.showLyricsInToolbar == "showLyricsInToolbar")
        #expect(UserDefaultsKeys.showSettingsInToolbar == "showSettingsInToolbar")
        #expect(UserDefaultsKeys.nowPlayingToolbarOrder == "nowPlayingToolbarOrder")
    }

    @Test func playerBehaviorKeys() {
        #expect(UserDefaultsKeys.disableSpinningArt == "disableSpinningArt")
        #expect(UserDefaultsKeys.rememberPlaybackPosition == "rememberPlaybackPosition")
        #expect(UserDefaultsKeys.enableMiniPlayerSwipe == "enableMiniPlayerSwipe")
        #expect(UserDefaultsKeys.showVolumeSlider == "showVolumeSlider")
        #expect(UserDefaultsKeys.showAudioQualityInfo == "showAudioQualityInfo")
        #expect(UserDefaultsKeys.showHeartInPlayer == "showHeartInPlayer")
        #expect(UserDefaultsKeys.showRatingInPlayer == "showRatingInPlayer")
        #expect(UserDefaultsKeys.showQueueInPlayer == "showQueueInPlayer")
    }

    @Test func appearanceExtendedKeys() {
        #expect(UserDefaultsKeys.enableLiquidGlass == "enableLiquidGlass")
        #expect(UserDefaultsKeys.enableMiniPlayerTint == "enableMiniPlayerTint")
        #expect(UserDefaultsKeys.albumBackgroundStyle == "albumBackgroundStyle")
    }

    @Test func tabBarExtendedKeys() {
        #expect(UserDefaultsKeys.settingsInNavBar == "settingsInNavBar")
        #expect(UserDefaultsKeys.showDownloadsTab == "showDownloadsTab")
        #expect(UserDefaultsKeys.showArtistsTab == "showArtistsTab")
        #expect(UserDefaultsKeys.showAlbumsTab == "showAlbumsTab")
        #expect(UserDefaultsKeys.showSongsTab == "showSongsTab")
        #expect(UserDefaultsKeys.showGenresTab == "showGenresTab")
        #expect(UserDefaultsKeys.showFavoritesTab == "showFavoritesTab")
        #expect(UserDefaultsKeys.tabBarOrder == "tabBarOrder")
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
            UserDefaultsKeys.crossfadeCurve,
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
            // Now Playing Toolbar
            UserDefaultsKeys.showVisualizerInToolbar,
            UserDefaultsKeys.showEQInToolbar,
            UserDefaultsKeys.showAirPlayInToolbar,
            UserDefaultsKeys.showLyricsInToolbar,
            UserDefaultsKeys.showSettingsInToolbar,
            UserDefaultsKeys.nowPlayingToolbarOrder,
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
            UserDefaultsKeys.lastFmUsername,
            // Adaptive Bitrate
            UserDefaultsKeys.adaptiveBitrateEnabled,
            // Player Behavior
            UserDefaultsKeys.disableSpinningArt,
            UserDefaultsKeys.rememberPlaybackPosition,
            UserDefaultsKeys.enableMiniPlayerSwipe,
            UserDefaultsKeys.showVolumeSlider,
            UserDefaultsKeys.showAudioQualityInfo,
            UserDefaultsKeys.showHeartInPlayer,
            UserDefaultsKeys.showRatingInPlayer,
            UserDefaultsKeys.showQueueInPlayer,
            // Appearance Extended
            UserDefaultsKeys.enableLiquidGlass,
            UserDefaultsKeys.enableMiniPlayerTint,
            UserDefaultsKeys.albumBackgroundStyle,
            // Tab Bar Extended
            UserDefaultsKeys.settingsInNavBar,
            UserDefaultsKeys.showDownloadsTab,
            UserDefaultsKeys.showArtistsTab,
            UserDefaultsKeys.showAlbumsTab,
            UserDefaultsKeys.showSongsTab,
            UserDefaultsKeys.showGenresTab,
            UserDefaultsKeys.showFavoritesTab,
            UserDefaultsKeys.tabBarOrder,
            // Library
            UserDefaultsKeys.libraryLayout,
            UserDefaultsKeys.activeMusicFolderId,
        ]
    }
}
