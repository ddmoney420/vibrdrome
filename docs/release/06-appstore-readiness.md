# 06 — App Store Readiness

## Submission Checklist

### Build & Signing
| Requirement | Status | Notes |
|-------------|--------|-------|
| Xcode Archive builds clean | Pending | Needs signing identity |
| Code signing identity | Pending | Requires Apple Developer account |
| Provisioning profiles (iOS + macOS) | Pending | Generate in App Store Connect |
| CarPlay entitlement approved | Pending | Must request from Apple via MFi portal |
| App icons (all sizes) | Ready | AppIcon in Assets.xcassets |
| Launch screen | Ready | Default SwiftUI launch |

### Info.plist Compliance
| Requirement | Status | Notes |
|-------------|--------|-------|
| `NSPrivacyAccessedAPITypes` | Done | UserDefaults (CA92.1), File Timestamps (C617.1) |
| `UIBackgroundModes` | Done | audio, fetch, processing |
| `CFBundleShortVersionString` | Done | 1.0.0 via MARKETING_VERSION |
| `CFBundleVersion` | Done | 1 via CURRENT_PROJECT_VERSION |
| CarPlay scene manifest | Done | CPTemplateApplicationScene configured |

### App Review Guidelines Compliance

**2.1 — App Completeness**
- All features functional (no placeholder screens)
- Dead features (gapless/crossfade) marked "Coming Soon" and disabled
- No debug-only features in release builds

**2.3 — Accurate Metadata**
- App description matches actual functionality
- Screenshots must show real app content
- No mention of unreleased features

**4.0 — Design (CarPlay)**
- Uses CPTemplate system (CPTabBarTemplate, CPListTemplate, CPNowPlayingTemplate)
- No custom UI in CarPlay — fully template-based
- Audio-only CarPlay app (compliant with HIG)
- Respects 200-item list limits

**5.1 — Privacy**
- No analytics or tracking SDKs
- No data collection beyond user's own server
- All data stored locally (SwiftData) or on user's server
- Credentials in Keychain (not UserDefaults)
- Server URL/username in UserDefaults (non-sensitive)

**5.1.1 — Data Collection and Storage**
- No third-party analytics
- No advertising identifiers
- No health, financial, or sensitive data

**5.1.2 — Data Use and Sharing**
- Zero data shared with third parties
- All network traffic goes only to user-configured Navidrome server

### Privacy Labels (App Store Connect)

**Data Not Collected:** The app does not collect any data.

Justification:
- No analytics SDKs (no Firebase, Amplitude, etc.)
- No crash reporting service (no Sentry, Crashlytics, etc.)
- No ad networks
- All music data fetched from user's own self-hosted server
- Credentials stored only on-device in Keychain
- No telemetry of any kind

### App Store Metadata

| Field | Value |
|-------|-------|
| App Name | Veydrune |
| Subtitle | Music Player for Navidrome |
| Category | Music |
| Secondary Category | Entertainment |
| Age Rating | 4+ |
| Price | Free (or chosen price tier) |
| Availability | All territories |

**Description (draft):**
> Veydrune is a beautiful, native music player for your Navidrome server. Stream your entire music library from anywhere with full CarPlay support, offline downloads, and a polished SwiftUI interface.
>
> Features:
> - Browse by artists, albums, genres, playlists, and favorites
> - Full playback controls with shuffle, repeat, and queue management
> - CarPlay integration for safe in-car listening
> - Download songs and albums for offline playback
> - Internet radio station streaming
> - Lyrics display (synced and unsynced)
> - Audio visualizer with real-time effects
> - Multi-server support — connect to multiple Navidrome instances
> - Dark mode, accent color themes, and accessibility options
> - Scrobbling support
> - Bookmarks for resuming long tracks
>
> Requires a Navidrome server (or any Subsonic-compatible server).

**Keywords:** navidrome, subsonic, music, player, streaming, carplay, offline, self-hosted, library, audio

**App Review Notes (template):**
> This app connects to a user-provided Navidrome music server (Subsonic API compatible). To test:
>
> 1. You will need a Navidrome server. A public demo is available at: https://demo.navidrome.org
>    - Username: demo
>    - Password: demo
> 2. Launch the app, enter the server URL, username, and password
> 3. Browse the music library, play songs, test queue/shuffle/repeat
> 4. CarPlay can be tested via Xcode CarPlay Simulator
>
> The app does not collect any user data. All communication is between the app and the user's own server.

### Screenshot Requirements

| Device | Size | Required |
|--------|------|----------|
| iPhone 6.7" (15 Pro Max/16 Pro Max) | 1290 x 2796 | Yes |
| iPhone 6.1" (15/16) | 1179 x 2556 | Yes |
| iPad 12.9" (6th gen) | 2048 x 2732 | If iPad supported |
| Mac | 1280 x 800 min | If Mac App Store |

**Suggested screenshot set (6-10):**
1. Library view (albums grid)
2. Now Playing (full screen with album art)
3. Artist detail with album list
4. Search results
5. CarPlay now playing
6. Playlist view
7. Downloads / offline
8. Settings (dark mode, accent colors)
9. Lyrics view
10. Queue management

### Signing & Provisioning Notes

1. **Apple Developer Program membership required** ($99/year)
2. **CarPlay Audio entitlement** — must be requested separately through Apple's CarPlay program. This is NOT automatic with a developer account. Apply at: https://developer.apple.com/carplay/
3. **Provisioning profiles** needed:
   - iOS App Store Distribution
   - macOS App Store Distribution (if submitting to Mac App Store)
   - Each must include the CarPlay entitlement (iOS only)
4. **App ID** must be registered with:
   - Associated CarPlay capability
   - Background Modes capability

### Pre-Submission Checklist

- [ ] Apple Developer account active
- [ ] CarPlay entitlement approved by Apple
- [ ] App ID registered with correct capabilities
- [ ] Provisioning profiles generated and valid
- [ ] Archive builds successfully in Xcode
- [ ] All screenshots captured at correct resolutions
- [ ] App description finalized
- [ ] Privacy policy URL hosted and accessible
- [ ] Support URL configured
- [ ] Age rating questionnaire completed
- [ ] Privacy labels filled in App Store Connect
- [ ] App Review notes with demo server credentials
- [ ] TestFlight beta testing completed
- [ ] No compiler warnings in release build
- [ ] All unit tests passing
