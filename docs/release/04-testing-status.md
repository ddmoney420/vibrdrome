# 04 — Testing Status

## Current State (April 2026)

| Metric | Value |
|--------|-------|
| Total tests (all platforms) | 924 |
| Total test files | 80 |
| Platforms tested | iOS, macOS, watchOS, Android, Web |
| All passing | Yes |
| CI | GitHub Actions (iOS/macOS), local (Android/Web) |

---

## iOS/macOS — 680 tests across 55 files

### Core Unit Tests — 495 tests, 32 files

Uses Swift Testing framework (`@Test`, `#expect`).

| Test File | Tests | Coverage |
|-----------|-------|----------|
| SubsonicEndpointsTests | 65 | All endpoint paths, query items, pagination offsets |
| SubsonicModelsTests | 55 | JSON decoding for all API model types |
| UtilityTests | 42 | Format helpers, string sanitization, error presenter |
| VolumeFactorTests | 26 | Volume computation, ReplayGain, sleep fade |
| QueueManagementTests | 23 | Add, remove, move, next, previous, shuffle |
| CacheEvictionTests | 20 | LRU eviction, pinned downloads, size limits |
| RadioDeduplicationTests | 19 | Radio song dedup, similar song filtering |
| SavedQueueTests | 18 | Queue persistence, round-trip encode/decode |
| SleepTimerTests | 17 | Timer modes, countdown, fade, end-of-track |
| CachedSongConversionTests | 17 | CachedSong to Song conversion |
| ReAuthTests | 16 | Re-authentication flows |
| LocalAddressTests | 16 | RFC 1918 detection, IPv6, link-local |
| EQPresetsTests | 14 | Preset definitions, band frequencies |
| UserDefaultsKeysTests | 13 | Key uniqueness, count, values |
| NowPlayingLayoutTests | 13 | Sleep timer formatting, duration, repeat mode |
| ReplayGainTests | 12 | dB-to-linear conversion, 1.5x cap, clamping |
| PlaybackModeTests | 12 | Gapless/crossfade mode selection |
| SubsonicAuthTests | 10 | Auth params, MD5 token, salt, password safety |
| QueueEdgeCaseTests | 10 | Empty queue, boundary conditions |
| LibraryLayoutConfigTests | 9 | Config encoding, pill/carousel management |
| SleepTimerFormattingTests | 8 | Time format edge cases |
| BiographyCleanerTests | 8 | HTML tag stripping, Last.fm format |
| EQPreGainTests | 7 | Pre-gain attenuation math, threshold |
| AudioSpectrumTests | 7 | FFT processing, spectrum bands |
| RatingEndpointTests | 6 | setRating API parameters |
| ListenBrainzTests | 6 | isEnabled logic, token/toggle state |
| LibraryPillTests | 6 | Pill count, config, reorder |
| DownloadedSongTests | 6 | toSong() conversion, nil handling |
| WidgetStateTests | 4 | NowPlayingState encode/decode |
| WidgetCommandTests | 4 | Command relay, TTL expiry |
| RadioCoverArtTests | 4 | Navidrome ra- prefix handling |
| AutoSuggestTests | 2 | Auto-suggest guard logic |

### iOS UI Tests — 95 tests, 11 files

Uses XCUITest framework.

| Test File | Tests | Coverage |
|-----------|-------|----------|
| NowPlayingFeatureTests | 23 | Player controls, rating, queue, EQ, lyrics |
| RotationTests | 12 | Device rotation stability |
| DownloadsAndSettingsTests | 12 | Download flow, settings toggles |
| RadioTests | 9 | Radio playback, station search |
| PlaylistTests | 9 | Playlist browsing, create, edit |
| NavigationTests | 9 | Tab navigation, artist/album drill-down |
| ReAuthAndEQAccessibilityTests | 7 | Re-auth flow, EQ accessibility |
| PlaybackTests | 7 | Play, pause, skip, seek |
| LaunchTests | 4 | App launch, initial state |
| LoginTests | 3 | Server config, authentication |
| TestHelpers | 0 | Shared utilities (no tests) |

### macOS UI Tests — 90 tests, 12 files

Uses XCUITest framework.

| Test File | Tests | Coverage |
|-----------|-------|----------|
| MacNowPlayingFeatureTests | 25 | Player controls, rating, queue |
| MacSettingsTests | 11 | Settings, preferences |
| MacNavigationTests | 10 | Sidebar navigation |
| MacRadioTests | 9 | Radio playback |
| MacPlaylistTests | 8 | Playlist management |
| MacWindowAndKeyboardTests | 6 | Window management, keyboard shortcuts |
| MacReAuthAndEQTests | 6 | Re-auth, EQ |
| MacPlaybackTests | 6 | Playback controls |
| MacFavoritesAndDownloadsTests | 4 | Favorites, downloads |
| MacLoginTests | 3 | Server login |
| MacLaunchTests | 2 | App launch |
| MacTestHelpers | 0 | Shared utilities (no tests) |

---

## Android — 124 tests across 14 files

Uses JUnit 5 with Kotlin.

### Audio Module — 9 files, 82 tests

| Test File | Tests | Coverage |
|-----------|-------|----------|
| ReplayGainTest | 12 | dB conversion, clamping |
| CrossfadeEngineTest | 11 | Crossfade curves, transitions |
| SmartTransitionsTest | 11 | Auto gapless/crossfade detection |
| AutoEQImporterTest | 11 | AutoEQ/APO file import |
| AdaptiveBitrateTest | 8 | Network-based quality adjustment |
| EQPresetsTest | 8 | Preset definitions |
| AudioNormalizerTest | 7 | Volume normalization |
| EQCoefficientsTest | 7 | Biquad coefficient computation |
| HapticEngineTest | 7 | Bass-synced haptic intensity |

### Network Module — 4 files, 38 tests

| Test File | Tests | Coverage |
|-----------|-------|----------|
| SubsonicErrorTest | 11 | Error code mapping |
| SubsonicEndpointsTest | 10 | Endpoint URL construction |
| SubsonicModelsTest | 10 | JSON model decoding |
| SubsonicAuthTest | 7 | Auth parameter generation |

### Utility Module — 1 file, 4 tests

| Test File | Tests | Coverage |
|-----------|-------|----------|
| FormatTest | 4 | Duration formatting |

---

## Web — 120 tests across 11 files

Uses Vitest with TypeScript.

### API Clients — 2 files, 27 tests

| Test File | Tests | Coverage |
|-----------|-------|----------|
| SubsonicClient.test.ts | 16 | API calls, auth, error handling |
| LastFmClient.test.ts | 11 | Last.fm scrobbling, artist info |

### Stores — 5 files, 64 tests

| Test File | Tests | Coverage |
|-----------|-------|----------|
| playerStore.test.ts | 27 | Playback state, queue, volume |
| uiStore.test.ts | 17 | Theme, layout, preferences |
| libraryStore.test.ts | 12 | Library browsing, caching |
| smartPlaylistStore.test.ts | 4 | Smart playlist generation |
| musicFolderStore.test.ts | 4 | Folder switching |

### Hooks — 1 file, 6 tests

| Test File | Tests | Coverage |
|-----------|-------|----------|
| useMultiSelect.test.ts | 6 | Multi-select state management |

### Utilities — 3 files, 23 tests

| Test File | Tests | Coverage |
|-----------|-------|----------|
| color.test.ts | 10 | Color extraction, contrast |
| fuzzySearch.test.ts | 10 | Fuzzy/acronym search matching |
| share.test.ts | 3 | Share text generation |

---

## Test Coverage Gaps

### Android
- No UI/instrumented tests (iOS has 185 UI tests)
- No ViewModel/Store tests (presentation layer untested)

### Web
- No component/rendering tests (all tests are logic-only)
- No E2E tests (no Playwright/Cypress)

### iOS
- Core unit tests are the most comprehensive across all platforms
- Good model for expanding Android and Web test suites

---

## Running Tests

```bash
# iOS/macOS
xcodebuild test -project Vibrdrome.xcodeproj -scheme Vibrdrome \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:VibrdromeTests

# Android
cd vibrdrome-android && ./gradlew test

# Web
cd vibrdrome-web && npm test
```
