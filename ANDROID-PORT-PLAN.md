# Vibrdrome Android Port Plan

Full 1:1 feature port from iOS to Android. Native Kotlin + Jetpack Compose.

---

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Language | Kotlin |
| UI | Jetpack Compose + Material 3 |
| Audio | ExoPlayer / Media3 |
| EQ DSP | ExoPlayer AudioProcessor (custom biquad) |
| Crossfade | Dual ExoPlayer instances |
| Android Auto | MediaLibraryService (Media3) |
| Networking | Ktor or Retrofit + kotlinx.serialization |
| Images | Coil (disk + memory caching) |
| Database | Room (replaces SwiftData) |
| Credentials | EncryptedSharedPreferences (replaces Keychain) |
| Downloads | WorkManager + foreground service |
| Visualizer | OpenGL ES fragment shaders (replaces Metal) |
| Concurrency | Kotlin Coroutines + Flow (replaces async/await + Combine) |
| DI | Koin or Hilt |

## iOS → Android Component Mapping

| iOS Component | Android Equivalent | Notes |
|---------------|-------------------|-------|
| `AudioEngine.swift` (987 lines) | `AudioEngine.kt` | Central state machine. Same architecture: mode enum, volume factors, queue management. ExoPlayer API instead of AVPlayer |
| `AudioEngine+Crossfade.swift` | `CrossfadeController.kt` | Dual ExoPlayer with coroutine-based 30Hz volume ramp timer. Same edge cases: cancel ramp on seek, clamp fade to 50% duration |
| `AudioEngine+Observers.swift` | `Player.Listener` callbacks | ExoPlayer uses `Player.Listener` interface instead of KVO/NotificationCenter |
| `AudioEngine+Radio.swift` | `RadioManager.kt` | Same logic: seed artist, blend primary/secondary, deduplicate, refill |
| `AudioEngine+QueuePersistence.swift` | `QueuePersistence.kt` with Room | Same save/restore pattern, Room instead of SwiftData |
| `EQTapProcessor.swift` (226 lines) | `BiquadAudioProcessor.kt` | Implement `AudioProcessor` interface. Port biquad math line-for-line. Process PCM in `queueInput()`/`getOutput()` |
| `EQCoefficients.swift` | `EQCoefficients.kt` | Same thread-safe coefficient store. Use `Mutex` or `synchronized` instead of `OSAllocatedUnfairLock` |
| `EQEngine.swift` | `EQEngine.kt` | Preset management, coefficient sync. Direct port |
| `EQPresets.swift` | `EQPresets.kt` | Pure constants — copy values directly |
| `CrossfadeController.swift` (142 lines) | `CrossfadeController.kt` | Dual ExoPlayer. `Handler`/coroutine timer instead of `Timer`. Same ramp math |
| `SleepTimer.swift` | `SleepTimer.kt` | Same countdown + fade logic. Use `CountDownTimer` or coroutine delay |
| `SubsonicClient.swift` (392 lines) | `SubsonicClient.kt` | Ktor HttpClient or Retrofit. Same retry logic, same auth, same endpoints |
| `SubsonicModels.swift` (370 lines) | `SubsonicModels.kt` | `data class` for each struct. Nearly line-for-line translation |
| `SubsonicEndpoints.swift` (270 lines) | `SubsonicEndpoints.kt` | Sealed class or enum. Same URL building |
| `SubsonicAuth.swift` | `SubsonicAuth.kt` | Same salt + MD5 token generation |
| `ResponseCache.swift` | `ResponseCache.kt` | Same file-based JSON cache in app cache directory |
| `DownloadManager.swift` (476 lines) | `DownloadManager.kt` | WorkManager for background scheduling. OkHttp for HTTP Range resume. Room for download records |
| `CacheManager.swift` | `CacheManager.kt` | Same LRU eviction logic |
| `PersistenceController.swift` | Room database + DAOs | Define `@Entity` classes for CachedSong, DownloadedSong, SavedQueue, PendingAction |
| `OfflineActionQueue.swift` | `OfflineActionQueue.kt` | Same pending/failed action pattern. WorkManager for retry |
| `NowPlayingManager.swift` | Part of MediaSession | Media3 `MediaSession` handles now playing info, artwork, and playback state automatically |
| `RemoteCommandManager.swift` | Part of MediaSession | Media3 handles lock screen, notification, headphone controls via `MediaSession.Callback` |
| `CarPlaySceneDelegate.swift` | Not needed | Android Auto uses service-based architecture, no scene delegate |
| `CarPlayManager.swift` (540 lines) | `AutoMediaLibraryService.kt` | Define browse tree: root → (Artists, Albums, Playlists, Radio, Recent) → items. Auto renders UI |
| `CarPlaySearchHandler.swift` | `onSearch()` in MediaLibraryService | Search callback in the library service |
| All SwiftUI Views (~7,600 lines) | Jetpack Compose screens | Same screen structure, Compose equivalents for NavigationStack, TabView, List, LazyVGrid, etc. |
| `Shaders.metal` (229 lines) | GLSL fragment shaders | Port 6 presets to OpenGL ES. Use `GLSurfaceView` + custom `Renderer` |
| `AppState.swift` | `AppState.kt` or ViewModel | `StateFlow` replaces `@Observable`. Same singleton pattern |
| `ReAuthView.swift` | `ReAuthDialog.kt` | Compose `AlertDialog` instead of `.sheet` |
| `Theme.swift` | `Theme.kt` + Material 3 theming | Compose `MaterialTheme` with custom color schemes |

## Project Structure

```
app/src/main/java/com/vibrdrome/
├── audio/
│   ├── AudioEngine.kt              # Central playback state machine
│   ├── CrossfadeController.kt      # Dual ExoPlayer crossfade
│   ├── BiquadAudioProcessor.kt     # 10-band EQ DSP (AudioProcessor)
│   ├── EQEngine.kt                 # Preset management
│   ├── EQCoefficients.kt           # Thread-safe coefficient store
│   ├── EQPresets.kt                # Preset definitions
│   ├── SleepTimer.kt               # Countdown + volume fade
│   ├── RadioManager.kt             # Artist/song radio generation
│   └── QueuePersistence.kt         # Save/restore queue via Room
├── network/
│   ├── SubsonicClient.kt           # API client with retry + caching
│   ├── SubsonicModels.kt           # Data classes
│   ├── SubsonicEndpoints.kt        # URL building
│   ├── SubsonicAuth.kt             # Salt + token auth
│   └── ResponseCache.kt            # File-based JSON cache
├── persistence/
│   ├── AppDatabase.kt              # Room database
│   ├── entities/                   # CachedSong, DownloadedSong, SavedQueue, PendingAction
│   └── dao/                        # Data access objects
├── downloads/
│   ├── DownloadManager.kt          # WorkManager + OkHttp
│   └── CacheManager.kt            # LRU eviction
├── auto/
│   └── AutoMediaLibraryService.kt  # Android Auto browse tree
├── ui/
│   ├── AppState.kt                 # Global observable state
│   ├── theme/
│   │   └── Theme.kt                # Material 3 + accent colors
│   ├── library/
│   │   ├── LibraryScreen.kt        # Home with quick access pills
│   │   ├── ArtistsScreen.kt
│   │   ├── AlbumsScreen.kt
│   │   ├── AlbumDetailScreen.kt
│   │   ├── ArtistDetailScreen.kt
│   │   ├── SongsScreen.kt
│   │   ├── GenerationsScreen.kt
│   │   ├── GenresScreen.kt
│   │   ├── FolderBrowserScreen.kt
│   │   ├── FolderIndexScreen.kt
│   │   ├── FolderDetailScreen.kt
│   │   ├── FavoritesScreen.kt
│   │   └── DownloadsScreen.kt
│   ├── player/
│   │   ├── NowPlayingScreen.kt
│   │   ├── MiniPlayer.kt
│   │   ├── QueueScreen.kt
│   │   ├── LyricsScreen.kt
│   │   ├── VisualizerScreen.kt     # GLSurfaceView in Compose
│   │   └── EQScreen.kt
│   ├── playlists/
│   │   ├── PlaylistsScreen.kt
│   │   ├── PlaylistDetailScreen.kt
│   │   ├── PlaylistEditorScreen.kt
│   │   └── SmartPlaylistScreen.kt
│   ├── radio/
│   │   ├── RadioScreen.kt
│   │   ├── StationSearchScreen.kt
│   │   └── AddStationScreen.kt
│   ├── search/
│   │   └── SearchScreen.kt
│   ├── settings/
│   │   ├── SettingsScreen.kt
│   │   ├── ServerConfigScreen.kt
│   │   ├── ServerManagerScreen.kt
│   │   └── ReAuthDialog.kt
│   └── components/
│       ├── AlbumArtView.kt
│       ├── AlbumCard.kt
│       ├── TrackContextMenu.kt
│       ├── StarButton.kt
│       └── ErrorPresenter.kt
├── visualizer/
│   ├── VisualizerRenderer.kt       # GLSurfaceView.Renderer
│   └── shaders/                    # GLSL fragment shaders (6 presets)
└── VibrdromedApp.kt                # Application class + DI setup
```

## Implementation Phases

### Phase 1: Walking Skeleton (Weeks 1-4)

**Goal:** Working app that connects to server, browses library, plays a track.

- [ ] Project setup: Gradle, dependencies, Material 3 theme
- [ ] `SubsonicAuth.kt` — salt + MD5 token generation
- [ ] `SubsonicModels.kt` — port all data classes from `SubsonicModels.swift`
- [ ] `SubsonicEndpoints.kt` — port URL building from `SubsonicEndpoints.swift`
- [ ] `SubsonicClient.kt` — Ktor client, retry logic, basic endpoints
- [ ] `ServerConfigScreen.kt` — login flow with URL/username/password
- [ ] `EncryptedSharedPreferences` for credential storage
- [ ] `AppState.kt` — global state with `StateFlow`
- [ ] Basic ExoPlayer setup with `MediaSession` + `MediaSessionService`
- [ ] Lock screen controls + notification (comes free with MediaSession)
- [ ] `LibraryScreen.kt` — quick access pills, recently added carousel
- [ ] `ArtistsScreen.kt`, `AlbumsScreen.kt`, `AlbumDetailScreen.kt`
- [ ] `NowPlayingScreen.kt` — artwork, controls, progress slider
- [ ] `MiniPlayer.kt` — bottom bar with play/pause/next
- [ ] Navigation setup with Compose Navigation
- [ ] Image loading with Coil + disk caching

**Reference files:**
- `SubsonicModels.swift` → direct translation to Kotlin data classes
- `SubsonicEndpoints.swift` → sealed class with path/queryItems
- `SubsonicClient.swift` → same retry/decode pattern
- `LibraryView.swift` → layout structure for home screen
- `AlbumDetailView.swift` → track list with context menu

### Phase 2: Core Audio (Weeks 5-8)

**Goal:** Full playback experience with queue management.

- [ ] Queue management: play, add to queue, play next, reorder, clear
- [ ] Gapless playback via ExoPlayer playlist mode (`addMediaItem`)
- [ ] Shuffle (random index, play count tracking)
- [ ] Repeat modes: `.all` (loop track via gapless), `.one` (repeat once then advance)
- [ ] Track end handling + auto-advance
- [ ] Seek with proper state management
- [ ] Playback speed (ExoPlayer `setPlaybackParameters`)
- [ ] `QueueScreen.kt` — drag to reorder, swipe to delete
- [ ] Queue persistence with Room (save on background, restore on launch)
- [ ] `SearchScreen.kt` — debounced search with results
- [ ] `GenresScreen.kt`, `SongsScreen.kt`, `GenerationsScreen.kt`
- [ ] `FavoritesScreen.kt` — starred artists, albums, songs
- [ ] `TrackContextMenu.kt` — play next, add to queue, star, go to album/artist
- [ ] `StarButton.kt` — star/unstar with API call

**Reference files:**
- `AudioEngine.swift` lines 290-560 — play(), next(), previous(), seek(), queue management
- `AudioEngine.swift` lines 501-543 — advanceIndex(), advanceShuffleIndex()
- `AudioEngine.swift` lines 949-968 — handleTrackEnd() with repeat mode logic
- `QueueView.swift` — queue UI structure

### Phase 3: Advanced Audio (Weeks 9-13)

**Goal:** Crossfade, EQ, ReplayGain, sleep timer — the audiophile features.

- [ ] `CrossfadeController.kt` — dual ExoPlayer with coroutine-based 30Hz volume ramp
  - Port edge cases: cancel ramp on seek, update both players for playback rate, clamp fade to 50% duration
  - Handle Android audio focus with shared audio session ID
- [ ] Mode selection: gapless vs crossfade per track boundary
- [ ] `BiquadAudioProcessor.kt` — implement ExoPlayer `AudioProcessor`
  - Port `BiquadCoefficients.parametric()` math (identical in Kotlin)
  - 10-band processing with per-channel delay state
  - Thread-safe coefficient updates via `EQCoefficients.kt`
- [ ] `EQEngine.kt` — preset management, save/load custom presets
- [ ] `EQScreen.kt` — 10 vertical sliders, preset buttons, save preset dialog
- [ ] ReplayGain calculation (same math as `computeReplayGainFactor`)
- [ ] Volume factor system: userVolume × replayGainFactor × sleepFadeFactor × crossfadeFactor
- [ ] `SleepTimer.kt` — countdown with volume fade in final 10 seconds
  - Options: 15, 30, 45, 60, 120 minutes, end of track
- [ ] Auto-retry on stream failure (2-second delay, reload track)

**Reference files:**
- `CrossfadeController.swift` — complete crossfade state machine (142 lines)
- `EQTapProcessor.swift` — biquad DSP processing (226 lines), direct port to AudioProcessor
- `EQCoefficients.swift` — thread-safe coefficient store
- `AudioEngine.swift` lines 89-116 — volume factor system and applyEffectiveVolume()
- `AudioEngine.swift` lines 266-286 — mode selection and teardown
- `SleepTimer.swift` — countdown + fade logic

### Phase 4: Content Features (Weeks 14-18)

**Goal:** Playlists, radio, lyrics, all the content management.

- [ ] `PlaylistsScreen.kt` — grid of playlists with context menu
- [ ] `PlaylistDetailScreen.kt` — tracks with play/shuffle/download/edit
- [ ] `PlaylistEditorScreen.kt` — create/edit with song search, drag reorder
- [ ] `SmartPlaylistScreen.kt` — 6 generator types (Artist Mix, Genre Mix, Similar Songs, Random Mix, B-Sides, Curated Weekly)
- [ ] `RadioManager.kt` — artist radio, song radio with blend/deduplicate/refill
  - Port `interleaveRadioSongs()` and `deduplicateRadioSongs()` directly
- [ ] `RadioScreen.kt` — station list, search, add custom URL
- [ ] `StationSearchScreen.kt` — radio-browser.info API integration
- [ ] `AddStationScreen.kt` — name, URL, homepage fields
- [ ] Internet radio streaming (ExoPlayer handles ICY streams natively)
- [ ] `LyricsScreen.kt` — synced lyrics with auto-scroll, tap to seek
- [ ] Scrobbling — fire-and-forget now-playing + submission
- [ ] `OfflineActionQueue.kt` — pending/failed action tracking with WorkManager retry
- [ ] `ResponseCache.kt` — file-based API response caching (stale-while-revalidate)

**Reference files:**
- `AudioEngine+Radio.swift` — complete radio logic (209 lines)
- `SmartPlaylistView.swift` — 6 generator types with UI
- `LyricsView.swift` — synced lyrics display
- `RadioView.swift`, `StationSearchView.swift`, `AddStationView.swift`
- `OfflineActionQueue.swift` — pending action architecture
- `ResponseCache.swift` — caching pattern

### Phase 5: Offline + Android Auto (Weeks 19-23)

**Goal:** Download management, offline playback, Android Auto.

- [ ] `DownloadManager.kt` — WorkManager for background scheduling
  - OkHttp for HTTP Range resume support
  - Foreground service notification for active downloads
  - Room entities for download tracking (DownloadedSong)
- [ ] `CacheManager.kt` — LRU eviction by last access date, configurable limit
- [ ] Offline playback — resolve local file if downloaded, stream otherwise (same as `resolveURL(for:)`)
- [ ] Auto-download favorites on star
- [ ] Download entire album/playlist
- [ ] `DownloadsScreen.kt` — active downloads with progress, completed with file sizes, swipe to delete
- [ ] `AutoMediaLibraryService.kt` — Android Auto browse tree:
  - Root → Artists, Albums, Playlists, Radio, Recently Played
  - Each node returns `MediaItem` list
  - `onSearch()` callback for voice/text search
  - Now playing automatically handled by MediaSession
- [ ] `ServerManagerScreen.kt` — add, switch, remove servers
- [ ] `ReAuthDialog.kt` — 401 re-auth modal
- [ ] Cache clearing on logout/server switch

**Reference files:**
- `DownloadManager.swift` — download architecture (476 lines)
- `CacheManager.swift` — LRU eviction
- `AudioEngine.swift` lines 880-904 — resolveURL() local-vs-stream logic
- `CarPlayManager.swift` — browse tree structure (540 lines), translate tabs/sections to MediaItem tree
- `CarPlaySearchHandler.swift` — search implementation
- `ReAuthView.swift` — re-auth flow

### Phase 6: Polish (Weeks 24-26)

**Goal:** Visualizer, settings, edge cases, release prep.

- [ ] `VisualizerRenderer.kt` — GLSurfaceView with custom Renderer
  - Port 6 Metal shader presets to GLSL fragment shaders
  - Audio energy input via Android `Visualizer` API (FFT/waveform)
  - Swipe gestures to cycle presets
  - Auto-hide controls after 4 seconds
- [ ] `SettingsScreen.kt` — all settings sections:
  - Server (connection status, test, manage, sign out)
  - Playback (WiFi/cellular quality, scrobbling, gapless, crossfade, ReplayGain, EQ)
  - Downloads (cache limit, auto-download favorites, storage used)
  - Appearance (theme: system/dark/light, accent color, album art in lists)
  - Accessibility (large text, bold text, reduce motion)
  - About (version, offline queue status, sync/retry/clear)
- [ ] `FolderBrowserScreen.kt`, `FolderIndexScreen.kt`, `FolderDetailScreen.kt`
- [ ] Tablet/large screen layouts (adaptive navigation)
- [ ] Dark/light theme with 10 accent colors
- [ ] Error handling and user-friendly error messages
- [ ] Edge cases:
  - Network transitions (WiFi ↔ cellular)
  - Very short tracks with crossfade
  - Rapid skip through tracks
  - Background playback during Doze mode
  - OEM battery optimization workarounds (Samsung, Xiaomi, etc.)
- [ ] Play Store listing prep: screenshots, description, privacy policy (vibrdrome.io/privacy-policy)
- [ ] Testing across API levels 24-35, multiple screen sizes

**Reference files:**
- `Shaders.metal` — 6 shader presets to port to GLSL
- `VisualizerView.swift` — gesture handling, preset picker, auto-hide
- `SettingsView.swift` — complete settings structure
- `FolderBrowserView.swift`, `FolderIndexView.swift`, `FolderDetailView.swift`

## Key Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| ExoPlayer AudioProcessor for EQ | High — different buffer/threading model than MTAudioProcessingTap | Start with a simple 3-band EQ to validate the pipeline, then expand to 10 bands. Test on multiple devices |
| Dual ExoPlayer crossfade + audio focus | Medium — two players on one audio session is unusual | Share audio session ID, manage AudioAttributes carefully. Test with Bluetooth and Android Auto |
| Background downloads killed by OEM | Medium — Samsung/Xiaomi/Huawei aggressively kill services | Use WorkManager with foreground service. Add user-facing "battery optimization" prompt. Test on multiple OEMs |
| Metal → OpenGL ES shader port | Medium — different shading languages | Consider simplifying to 3-4 presets for v1. GLSL is well-documented. Alternatively, use Compose Canvas animations as a simpler v1 visualizer |
| Android fragmentation | Low-medium — notification/lock screen varies by OEM | Use Media3 which handles most OEM differences. Test on Samsung, Pixel, Xiaomi at minimum |
| Learning curve (Kotlin + Android) | Schedule risk | Kotlin is syntactically similar to Swift. Compose is conceptually similar to SwiftUI. Budget extra time in Phase 1 for tooling/ecosystem learning |

## Dependencies (Gradle)

```kotlin
// Media3 / ExoPlayer
implementation("androidx.media3:media3-exoplayer:1.5.1")
implementation("androidx.media3:media3-session:1.5.1")
implementation("androidx.media3:media3-ui:1.5.1")

// Compose
implementation(platform("androidx.compose:compose-bom:2025.01.01"))
implementation("androidx.compose.material3:material3")
implementation("androidx.compose.ui:ui")
implementation("androidx.navigation:navigation-compose:2.8.5")

// Networking
implementation("io.ktor:ktor-client-android:3.0.3")
implementation("io.ktor:ktor-client-content-negotiation:3.0.3")
implementation("io.ktor:ktor-serialization-kotlinx-json:3.0.3")

// Images
implementation("io.coil-kt:coil-compose:2.7.0")

// Database
implementation("androidx.room:room-runtime:2.7.0")
implementation("androidx.room:room-ktx:2.7.0")
ksp("androidx.room:room-compiler:2.7.0")

// Security
implementation("androidx.security:security-crypto:1.1.0-alpha07")

// Background work
implementation("androidx.work:work-runtime-ktx:2.10.0")

// DI
implementation("io.insert-koin:koin-androidx-compose:4.0.1")
```

## Open Source References (study only — GPL, do not copy code)

- **Ultrasonic** — github.com/ultrasonic/ultrasonic (GPL-3.0, Kotlin, most mature Subsonic client)
- **Tempo** — github.com/CappielloAntonio/tempo (AGPL-3.0, Kotlin + Compose + Media3)

## Safe to Use (Apache 2.0)

- **Google UAMP** — github.com/android/uamp (official Media3 sample app)
- **Media3 documentation** — developer.android.com/media/media3
- **ExoPlayer AudioProcessor docs** — developer.android.com/reference/androidx/media3/common/audio/AudioProcessor
