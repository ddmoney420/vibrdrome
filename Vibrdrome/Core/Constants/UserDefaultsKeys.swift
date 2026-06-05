import Foundation

// MARK: - Notification Names

extension Notification.Name {
    /// Posted to navigate to the Search view and focus its search bar.
    static let navigateToSearch = Notification.Name("com.vibrdrome.navigateToSearch")
    /// Posted to focus the search bar in the currently visible view.
    static let focusSearchBar = Notification.Name("com.vibrdrome.focusSearchBar")
    /// Posted when a song's starred state changes. userInfo: ["id": String, "starred": Bool]
    static let songStarredChanged = Notification.Name("com.vibrdrome.songStarredChanged")
    /// Posted when a song's rating changes. userInfo: ["id": String, "rating": Int]
    static let songRatingChanged = Notification.Name("com.vibrdrome.songRatingChanged")
}

/// Centralized UserDefaults key constants.
/// Use with both `UserDefaults.standard` and `@AppStorage`.
enum UserDefaultsKeys {

    // MARK: - Server

    static let serverURL = "serverURL"
    static let username = "username"
    static let savedServers = "savedServers"
    static let activeServerId = "activeServerId"
    /// Hosts the user has explicitly confirmed connecting to over unencrypted
    /// public HTTP (A-1 / Option 3). Stored as an array of lowercased host strings.
    static let acknowledgedInsecureHosts = "acknowledgedInsecureHosts"

    // MARK: - Audio Playback

    static let gaplessPlayback = "gaplessPlayback"
    static let crossfadeDuration = "crossfadeDuration"
    static let crossfadeCurve = "crossfadeCurve"
    /// When the server has no lyrics, look them up on LRCLIB (sends track metadata
    /// to a third party). Default on.
    static let fetchInternetLyrics = "fetchInternetLyrics"
    /// Per-song synced-lyrics timing nudge, in milliseconds (#86). Positive = lyrics
    /// advance earlier relative to the audio.
    static func lyricsOffset(songId: String) -> String { "lyricsOffset.\(songId)" }
    static let replayGainMode = "replayGainMode"
    static let scrobblingEnabled = "scrobblingEnabled"
    static let preloadSongs = "preloadSongs"
    static let keepSongsInCacheAfterPlayback = "keepSongsInCacheAfterPlayback"
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
    static let gridDensity = "gridDensity"
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

    // MARK: - macOS Track Table Columns

    /// Key prefix for per-view column config. Full key = prefix + viewKey (e.g. "songs", "album").
    static let trackTableColumnsPrefix = "trackTableColumns_"

    // MARK: - macOS Artist Links

    static let artistExternalLinks = "artistExternalLinks"

    // MARK: - macOS Layout

    static let macHomeLayout = "macHomeLayout"
    static let macNowPlayingPlacement = "macNowPlayingPlacement"
    static let macSidePanelMechanic = "macSidePanelMechanic"
    static let macSidePanelWidth = "macSidePanelWidth"
    static let macMiniPlayerPanelTrigger = "macMiniPlayerPanelTrigger"

    // MARK: - Advanced Filter Rule Sets

    static let albumFilterRuleSet = "albumFilterRuleSet"
    static let songFilterRuleSet = "songFilterRuleSet"
    static let artistFilterRuleSet = "artistFilterRuleSet"
    static let albumFilterRuleBuilderExpanded = "albumFilterRuleBuilderExpanded"
    static let songFilterRuleBuilderExpanded = "songFilterRuleBuilderExpanded"
    static let artistFilterRuleBuilderExpanded = "artistFilterRuleBuilderExpanded"

    // MARK: - Playlist Export

    static let exportDefaultFolderBookmark = "exportDefaultFolderBookmark"
    static let exportDefaultSyncMode = "exportDefaultSyncMode"
    static let exportDefaultTranscodeFormat = "exportDefaultTranscodeFormat"
    static let exportDefaultTranscodeBitrate = "exportDefaultTranscodeBitrate"
    static let exportFfmpegPath = "exportFfmpegPath"
    static let exportAutoSyncOnForeground = "exportAutoSyncOnForeground"

    // MARK: - Library Sync

    static let lastLibrarySyncDate = "lastLibrarySyncDate"
    static let lastFullSyncDate = "lastFullSyncDate"
    static let lastServerModified = "lastServerModified"
    static let backgroundSyncEnabled = "backgroundSyncEnabled"
    static let syncPollingInterval = "syncPollingInterval"
    static let lastCoverArtPrefetchDate = "lastCoverArtPrefetchDate"
}
