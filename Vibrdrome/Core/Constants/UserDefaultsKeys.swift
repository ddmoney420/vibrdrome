import Foundation

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
    static let replayGainMode = "replayGainMode"
    static let scrobblingEnabled = "scrobblingEnabled"

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
    static let boldText = "boldText"
    static let reduceMotion = "reduceMotion"
    static let disableVisualizer = "disableVisualizer"
    static let visualizerWarningShown = "visualizerWarningShown"
    static let showAlbumArtInLists = "showAlbumArtInLists"
    static let visualizerPreset = "visualizerPreset"

    // MARK: - Library Layout

    static let libraryLayout = "libraryLayout"
    static let activeMusicFolderId = "activeMusicFolderId"
}
