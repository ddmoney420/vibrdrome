import AppIntents

// MARK: - Play Favorites

struct PlayFavoritesIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Play Favorites"
    nonisolated static let description = IntentDescription("Play your starred/favorite songs")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard AppState.shared.isConfigured else {
            throw IntentError.notConfigured
        }
        let starred = try await AppState.shared.subsonicClient.getStarred()
        guard var songs = starred.song, !songs.isEmpty else {
            throw IntentError.noContent
        }
        songs.shuffle()
        AudioEngine.shared.play(song: songs[0], from: songs)
        return .result()
    }
}

// MARK: - Play Random Mix

struct PlayRandomMixIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Play Random Mix"
    nonisolated static let description = IntentDescription("Play a random mix of songs from your library")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard AppState.shared.isConfigured else {
            throw IntentError.notConfigured
        }
        let songs = try await AppState.shared.subsonicClient.getRandomSongs(size: 50)
        guard let first = songs.first else {
            throw IntentError.noContent
        }
        AudioEngine.shared.play(song: first, from: songs)
        return .result()
    }
}

// MARK: - Play Artist Radio

struct PlayArtistRadioIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Play Artist Radio"
    nonisolated static let description = IntentDescription("Start a radio mix based on an artist")
    static let openAppWhenRun = true

    @Parameter(title: "Artist Name")
    var artistName: String

    @MainActor
    func perform() async throws -> some IntentResult {
        guard AppState.shared.isConfigured else {
            throw IntentError.notConfigured
        }
        AudioEngine.shared.startRadio(artistName: artistName)
        return .result()
    }
}

// MARK: - Pause/Resume

struct TogglePlaybackIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Toggle Playback"
    nonisolated static let description = IntentDescription("Play or pause the current track")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AudioEngine.shared.togglePlayPause()
        return .result()
    }
}

// MARK: - Skip Track

struct SkipTrackIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Skip Track"
    nonisolated static let description = IntentDescription("Skip to the next track")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AudioEngine.shared.next()
        return .result()
    }
}

// MARK: - Errors

enum IntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case notConfigured
    case noContent

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notConfigured: "Vibrdrome is not connected to a server. Open the app to sign in."
        case .noContent: "No songs found."
        }
    }
}

// MARK: - App Shortcuts Provider

struct VibrdromeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayFavoritesIntent(),
            phrases: [
                "Play my favorites in \(.applicationName)",
                "Play starred songs in \(.applicationName)",
            ],
            shortTitle: "Play Favorites",
            systemImageName: "heart.fill"
        )
        AppShortcut(
            intent: PlayRandomMixIntent(),
            phrases: [
                "Play a random mix in \(.applicationName)",
                "Shuffle my music in \(.applicationName)",
            ],
            shortTitle: "Random Mix",
            systemImageName: "dice.fill"
        )
    }
}
