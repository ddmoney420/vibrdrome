import Foundation

// MARK: - Notification Names

extension Notification.Name {
    /// Posted to navigate to the Search view and focus its search bar.
    static let navigateToSearch = Notification.Name("com.vibrdrome.navigateToSearch")
    /// Posted to focus the search bar in the currently visible view.
    static let focusSearchBar = Notification.Name("com.vibrdrome.focusSearchBar")
}

/// Centralized UserDefaults key constants.
/// Use with both `UserDefaults.standard` and `@AppStorage`.
enum UserDefaultsKeys {

    // MARK: - Server

    static let serverURL = "serverURL"
    static let username = "username"
    static let savedServers = "savedServers"
    static let activeServerId = "activeServerId"

    // MARK: - Audio Playback

    static let gaplessPlayback = "gaplessPlayback"
    static let crossfadeDuration = "crossfadeDuration"
    static let crossfadeCurve = "crossfadeCurve"
    static let replayGainMode = "replayGainMode"
    static let scrobblingEnabled = "scrobblingEnabled"
    static let autoSuggestEnabled = "autoSuggestEnabled"

    // MARK: - Equalizer

    static let eqEnabled = "eqEnabled"
    static let eqCurrentPresetId = "eqCurrentPresetId"
    static let eqCurrentGains = "eqCurrentGains"
    static let customEQPresets = "customEQPresets"

    // MARK: - Downloads & Cache

    static let autoDownloadFavorites = "autoDownloadFavorites"
    static let downloadOverCellular = "downloadOverCellular"
    static let cacheLimitBytes = "cacheLimitBytes"

    // MARK: - Streaming

    static let wifiMaxBitRate = "wifiMaxBitRate"
    static let cellularMaxBitRate = "cellularMaxBitRate"

    // MARK: - CarPlay

    static let carPlayShowRadio = "carPlayShowRadio"
    static let carPlayShowGenres = "carPlayShowGenres"
    static let carPlayRecentCount = "carPlayRecentCount"

    // MARK: - Appearance

    static let appColorScheme = "appColorScheme"
    static let accentColorTheme = "accentColorTheme"
    static let largerText = "largerText"
    static let textSize = "textSize"
    static let autoSyncPlaylists = "autoSyncPlaylists"
    static let showSearchTab = "showSearchTab"
    static let showPlaylistsTab = "showPlaylistsTab"
    static let showRadioTab = "showRadioTab"
    static let boldText = "boldText"
    static let reduceMotion = "reduceMotion"
    static let disableVisualizer = "disableVisualizer"
    static let visualizerWarningShown = "visualizerWarningShown"
    static let showAlbumArtInLists = "showAlbumArtInLists"
    static let visualizerPreset = "visualizerPreset"

    // MARK: - Now Playing Toolbar

    static let showVisualizerInToolbar = "showVisualizerInToolbar"
    static let showEQInToolbar = "showEQInToolbar"
    static let showAirPlayInToolbar = "showAirPlayInToolbar"
    static let showLyricsInToolbar = "showLyricsInToolbar"
    static let showSettingsInToolbar = "showSettingsInToolbar"
    static let showRadioMixInToolbar = "showRadioMixInToolbar"
    static let nowPlayingToolbarBackground = "nowPlayingToolbarBackground"
    static let nowPlayingToolbarOrder = "nowPlayingToolbarOrder"

    // MARK: - Discord

    static let discordRPCEnabled = "discordRPCEnabled"

    // MARK: - ListenBrainz

    static let listenBrainzEnabled = "listenBrainzEnabled"
    static let listenBrainzToken = "listenBrainzToken"

    // MARK: - Last.fm

    static let lastFmEnabled = "lastFmEnabled"
    static let lastFmApiKey = "lastFmApiKey"
    static let lastFmSecret = "lastFmSecret"
    static let lastFmSessionKey = "lastFmSessionKey"
    static let lastFmUsername = "lastFmUsername"

    // MARK: - Adaptive Bitrate

    static let adaptiveBitrateEnabled = "adaptiveBitrateEnabled"

    // MARK: - ReplayGain Pre-Gain

    static let replayGainPreGainDb = "replayGainPreGainDb"
    static let replayGainFallbackDb = "replayGainFallbackDb"

    // MARK: - Player Behavior

    static let disableSpinningArt = "disableSpinningArt"
    static let rememberPlaybackPosition = "rememberPlaybackPosition"
    static let enableMiniPlayerSwipe = "enableMiniPlayerSwipe"
    static let showVolumeSlider = "showVolumeSlider"
    static let showAudioQualityInfo = "showAudioQualityInfo"
    static let showHeartInPlayer = "showHeartInPlayer"
    static let showRatingInPlayer = "showRatingInPlayer"
    static let showQueueInPlayer = "showQueueInPlayer"

    // MARK: - Appearance Extended

    static let enableLiquidGlass = "enableLiquidGlass"
    static let enableMiniPlayerTint = "enableMiniPlayerTint"
    static let albumBackgroundStyle = "albumBackgroundStyle"
    static let gridColumnsPerRow = "gridColumnsPerRow"
    static let showLosslessBadge = "showLosslessBadge"

    // MARK: - Tab Bar Extended

    static let settingsInNavBar = "settingsInNavBar"
    static let showDownloadsTab = "showDownloadsTab"
    static let showArtistsTab = "showArtistsTab"
    static let showAlbumsTab = "showAlbumsTab"
    static let showSongsTab = "showSongsTab"
    static let showGenresTab = "showGenresTab"
    static let showFavoritesTab = "showFavoritesTab"
    static let showLibraryHomeTab = "showLibraryHomeTab"
    static let tabBarOrder = "tabBarOrder"

    // MARK: - Library Layout

    static let libraryLayout = "libraryLayout"
    static let activeMusicFolderId = "activeMusicFolderId"

    // MARK: - macOS Layout

    static let macNowPlayingPlacement = "macNowPlayingPlacement"
    static let macSidePanelMechanic = "macSidePanelMechanic"
    static let macSidePanelWidth = "macSidePanelWidth"
    static let macMiniPlayerPanelTrigger = "macMiniPlayerPanelTrigger"

    // MARK: - Library Sync

    static let lastLibrarySyncDate = "lastLibrarySyncDate"
    static let lastFullSyncDate = "lastFullSyncDate"
    static let lastServerModified = "lastServerModified"
    static let backgroundSyncEnabled = "backgroundSyncEnabled"
    static let syncPollingInterval = "syncPollingInterval"
}
