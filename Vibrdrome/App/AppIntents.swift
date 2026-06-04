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

// MARK: - Play Playlist

struct PlayPlaylistIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Play Playlist"
    nonisolated static let description = IntentDescription("Play one of your playlists by name")
    static let openAppWhenRun = true

    @Parameter(title: "Playlist Name")
    var playlistName: String

    @MainActor
    func perform() async throws -> some IntentResult {
        guard AppState.shared.isConfigured else {
            throw IntentError.notConfigured
        }
        let target = playlistName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { throw IntentError.playlistNotFound }

        let playlists = try await AppState.shared.subsonicClient.getPlaylists()
        // Prefer an exact (case-insensitive) name match, then fall back to a substring
        // match so "chill" finds "Chill Vibes".
        guard let match = playlists.first(where: { $0.name.lowercased() == target })
            ?? playlists.first(where: { $0.name.lowercased().contains(target) }) else {
            throw IntentError.playlistNotFound
        }

        let full = try await AppState.shared.subsonicClient.getPlaylist(id: match.id)
        guard let songs = full.entry, !songs.isEmpty else {
            throw IntentError.noContent
        }
        AudioEngine.shared.play(song: songs[0], from: songs)
        return .result()
    }
}

// MARK: - Errors

enum IntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case notConfigured
    case noContent
    case playlistNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notConfigured: "Vibrdrome is not connected to a server. Open the app to sign in."
        case .noContent: "No songs found."
        case .playlistNotFound: "No playlist with that name was found."
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
        // PlayPlaylistIntent is intentionally not given a built-in phrase: a phrase
        // placeholder must be an AppEntity/AppEnum, not the String name parameter. The
        // intent is still available in the Shortcuts app, where the user can supply the
        // playlist name and assign their own Siri phrase. A PlaylistAppEntity would
        // enable a native "Play playlist X" phrase as a future enhancement.
    }
}
