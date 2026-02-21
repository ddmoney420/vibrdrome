# Veydrune Market Survey: iOS/macOS Subsonic Music Players

**Date:** 2026-02-21
**Purpose:** Competitive analysis of Subsonic/Navidrome client apps to inform Veydrune's v1.0 positioning and post-launch roadmap.

---

## 1. Competitor Profiles

### play:Sub (iOS)
- **Developer:** Michaels Apps (Michael Hansen)
- **Price:** $4.99 USD (one-time) + optional tip jar ($1.99-$8.99)
- **Latest version:** 2026.1.22
- **Status:** Actively maintained; recent iOS 26 compatibility fixes and CarPlay rewrite.
- **Positioning:** The premium, feature-rich Subsonic client for iOS. Broadest server compatibility and polished audio engine with gapless, crossfade, hi-res audio, and a 10-band EQ.
- **Sources:** [App Store](https://apps.apple.com/us/app/play-sub-music-streamer/id955329386), [Developer Site](https://michaelsapps.dk/playsubapp/)

### Amperfy (iOS / iPadOS / macOS)
- **Developer:** BLeeEZ (Dirk Hildebrand) -- open source (GPLv3)
- **Price:** Free
- **Latest version:** 2.0.0 (Feb 17, 2026)
- **Status:** Very actively developed; frequent releases with major feature additions. Raised deployment target to iOS 26 / macOS 26.
- **Positioning:** The open-source Swiss Army knife. Supports both Ampache and Subsonic APIs, with CarPlay, gapless playback, podcasts, radio, EQ, and as of v2.0.0: audio visualizer, spectrum analyzer, and replay gain.
- **Sources:** [GitHub](https://github.com/BLeeEZ/amperfy), [App Store](https://apps.apple.com/us/app/amperfy-music/id1530145038)

### SubStreamer (iOS + Android)
- **Developer:** ghenry22
- **Price:** Free
- **Latest version:** Updated in 2025
- **Status:** Maintained but infrequent updates. Cross-platform (iOS + Android).
- **Positioning:** The no-cost, no-frills option. Targets users who want basic streaming, offline, and podcast support without paying anything. Last.fm integration for discovery.
- **Sources:** [Developer Site](https://substreamerapp.com/), [App Store](https://apps.apple.com/us/app/substreamer/id1012991665)

### iSub (iOS)
- **Developer:** Ben Baron (einsteinx2) -- open source (GPLv3)
- **Price:** Free (was previously paid; now free)
- **Latest version:** 4.0.2 (last significant update ~2021)
- **Status:** Effectively in maintenance mode. Developer acknowledged lacking time for the planned Swift rewrite. Will accept PRs and keep it running on new iOS versions, but no active feature development.
- **Positioning:** The OG Subsonic client for iOS. Still functional with a solid feature set (gapless, EQ, offline, bookmarks, lyrics), but aging UI and no modern platform features.
- **Sources:** [Official Site](https://isub.app/), [GitHub](https://github.com/einsteinx2/iSubMusicStreamer), [App Store](https://apps.apple.com/us/app/isub-music-streamer/id362920532)

### Symfonium (Android)
- **Developer:** Tolriq (solo developer)
- **Price:** ~$5.99 USD one-time (free trial via Google Play)
- **Latest version:** 13.7.0 (Jan 2026)
- **Status:** Extremely active development. Frequent updates, 4.8-star rating, 450K+ installs. The gold standard for Android self-hosted music playback.
- **Positioning:** Premium universal music player. Connects to nearly everything (Plex, Emby, Jellyfin, Subsonic, SMB, WebDAV, cloud). Advanced EQ (up to 256 bands), synced lyrics, bookmarks, Android Auto, Chromecast, UPnP/DLNA, Sonos, Wear OS, Android TV. Not available on iOS -- represents the feature bar users expect.
- **Sources:** [Official Site](https://symfonium.app/), [Google Play](https://play.google.com/store/apps/details?id=app.symfonik.music.player)

---

## 2. Feature Comparison Matrix

| Feature | **Veydrune** | **play:Sub** | **Amperfy** | **SubStreamer** | **iSub** | **Symfonium** |
|---|---|---|---|---|---|---|
| **Platform** | iOS + macOS | iOS | iOS + macOS | iOS + Android | iOS | Android |
| **CarPlay / Auto** | Full (browse, search, now playing, favorites) | Yes (rewritten from scratch) | Yes | No confirmed support | No | Android Auto (full) |
| **Offline downloads** | Song + album (background URLSession) | Auto-cache + manual cache | Yes (full offline mode) | Yes | Yes (WiFi sync + auto-cache) | Yes (manual + auto cache) |
| **Queue mgmt** | Shuffle, repeat (off/all/one), drag reorder | Shuffle, repeat | Shuffle, repeat | Basic | Shuffle, repeat 1, repeat all | Multiple queues, full reorder |
| **Gapless playback** | Not yet (planned) | Yes | Yes | Not confirmed | Yes | Yes |
| **UI / Framework** | SwiftUI native (iOS 17+, macOS 14+) | UIKit (mature) | UIKit + Catalyst | Cross-platform | UIKit (aging) | Native Android (Material You) |
| **macOS support** | Yes (native SwiftUI) | No | Yes (Catalyst) | No (web client exists) | No | No (Android only) |
| **Multi-server** | Yes | Yes | Yes (Ampache + Subsonic) | Yes (cross-server playlists) | Yes | Yes (Plex, Emby, Jellyfin, Subsonic, SMB, WebDAV, cloud) |
| **Lyrics** | Synced + unsynced | Yes (Navidrome) | Synced + unsynced (Subsonic) | Yes (stored offline) | Yes (Subsonic API) | Synced + embedded + provider |
| **Internet radio** | Yes | Yes (20,000+ stations) | Yes (Ampache + Subsonic API) | Genre-based radio feature | Not confirmed | Yes |
| **Bookmarks** | Yes (long tracks) | Yes (audiobook-friendly) | Not confirmed | Yes (offline bookmarks) | Yes | Yes (Subsonic bookmarks API) |
| **Audio visualizer** | Metal shader visualizer | No | Yes (visualizer + spectrum, v2.0.0) | No | No | Not confirmed |
| **Equalizer** | No | 10-band + presets | Yes + replay gain | No | Full parametric EQ | Up to 256 bands, AutoEQ |
| **Crossfade** | No | Yes | No | No | No | Yes (Smart Fades) |
| **Podcast support** | No | Yes | Yes | Yes | No | Yes (audiobook features) |
| **Scrobbling** | No | Not confirmed | Yes | Yes (Last.fm) | Not confirmed | Not confirmed |
| **Chromecast / DLNA** | No | Yes (Chromecast + Jukebox) | No | No | No | Yes (Chromecast, UPnP/DLNA, Sonos) |
| **Siri / Shortcuts** | No | Not confirmed | Yes (Siri + Shortcuts + App Intents) | No | No | N/A (Android) |
| **Open source** | No | No | Yes (GPLv3) | No | Yes (GPLv3) | No |
| **Active development** | Pre-release (v1.0 imminent) | Active (monthly updates) | Very active (major releases) | Low cadence | Maintenance only | Very active (frequent updates) |
| **Price** | Free (TBD) | $4.99 | Free | Free | Free | ~$5.99 |

---

## 3. Competitive Landscape Analysis

### The iOS Subsonic Client Market (early 2026)

The iOS Subsonic client space is small but increasingly competitive:

- **play:Sub** is the incumbent premium option. It covers the most ground on audio features (gapless, crossfade, hi-res, EQ) and has the broadest server support. Its weakness is lack of macOS support and no audio visualizer.

- **Amperfy** is the rising challenger. Open source, free, with rapid development velocity. The v2.0.0 release added an audio visualizer and spectrum analyzer, closing feature gaps. It runs on macOS via Catalyst. Its weakness is a UIKit-based UI that feels less native on modern iOS/macOS, and Catalyst apps often feel like second-class citizens on Mac.

- **SubStreamer** serves the "just works, free" segment. No CarPlay, basic UI, but zero cost and cross-platform. Not a serious threat to a polished app.

- **iSub** is effectively legacy. Still functional, open source, but the developer has stepped back. No CarPlay, aging interface, no modern features. Relevant only as a cautionary tale about sustainability.

- **Symfonium** (Android) sets the feature ceiling. Any iOS user switching from Android -- or reading recommendations on r/selfhosted -- will benchmark against Symfonium's capabilities. Its breadth of server support, casting, EQ depth, and polish represent what a "best-in-class" self-hosted music player looks like.

### Market Gaps

1. **No SwiftUI-native Subsonic client exists.** Every iOS competitor uses UIKit or Catalyst. Veydrune is the first to offer a ground-up SwiftUI experience.
2. **CarPlay quality varies widely.** play:Sub rewrote theirs; Amperfy supports it; others do not. Deep CarPlay integration is still a differentiator.
3. **macOS is underserved.** Only Amperfy (via Catalyst) offers macOS, and Catalyst apps feel compromised. A native SwiftUI macOS experience is wide open.
4. **Audio visualizers are rare.** Only Amperfy (as of v2.0.0) and Veydrune offer them on iOS. Veydrune's Metal shader approach is technically superior.

---

## 4. Veydrune's Positioning

### 4.1 Three Key Differentiators Veydrune Can Own

**1. The only SwiftUI-native Subsonic client (iOS + macOS)**
Every competitor uses UIKit, Catalyst, or cross-platform frameworks. Veydrune's SwiftUI foundation means it looks, feels, and behaves like a first-party Apple app. On macOS, this is especially stark -- Amperfy's Catalyst port is the only alternative, and Catalyst apps carry inherent UX compromises (menu bar integration, window management, keyboard shortcuts). Veydrune's native NavigationSplitView sidebar and platform-conditional UI (`.sheet` vs `.fullScreenCover`, keyboard shortcuts like Cmd+P) deliver a Mac experience no competitor matches.

**2. Full CarPlay with search, browse, favorites, and now playing**
While play:Sub and Amperfy support CarPlay, Veydrune's implementation covers the complete surface area: hierarchical browsing, search, favorites access, and a full now-playing experience. Combined with the SwiftUI-native phone UI and offline downloads, this makes Veydrune the best option for users who split time between phone, car, and desktop.

**3. Metal shader audio visualizer**
Only Amperfy (v2.0.0) offers a visualizer on iOS, and theirs is a spectrum analyzer. Veydrune's Metal shader visualizer is GPU-accelerated and visually distinctive -- a feature that screenshots well, demos well, and creates an emotional connection with the app that pure utility features cannot.

### 4.2 Three Gaps to Address

**1. Gapless playback (CRITICAL for v1.0)**
Every serious competitor (play:Sub, Amperfy, iSub, Symfonium) supports gapless playback. For users with live albums, classical music, DJ mixes, or concept albums, gaps between tracks are a dealbreaker. This is the single most-requested feature in self-hosted music communities and the most conspicuous omission in Veydrune's current feature set.

**2. Equalizer**
play:Sub has a 10-band EQ. Amperfy has one. iSub has a parametric EQ. Symfonium has up to 256 bands. Veydrune has none. While not every user touches EQ settings, audiophile-oriented self-hosters (a large portion of the Navidrome user base) consider it essential. At minimum, a basic 5-10 band EQ with presets is needed.

**3. Scrobbling (Last.fm / ListenBrainz)**
Self-hosted music users overwhelmingly track their listening habits. Last.fm and ListenBrainz scrobbling is table-stakes for this audience. SubStreamer has Last.fm integration. Amperfy has scrobbling built in. Without it, Veydrune loses a significant cohort of potential users who refuse to use a player that does not scrobble.

---

## 5. Prioritized Feature Roadmap

### P0 -- Required for v1.0 Launch

| Feature | Rationale |
|---|---|
| **Gapless playback** | Parity with every serious competitor. Dealbreaker for live/classical/mix listeners. Without it, reviews will lead with "no gapless." |
| **EQ (basic 5-10 band)** | Expected by the audiophile self-hoster demographic. Does not need to match Symfonium's 256 bands, but must exist. |
| **Last.fm / ListenBrainz scrobbling** | Table-stakes for the target audience. Low implementation effort, high user expectation. |
| **Error handling polish** | Retry logic, offline graceful degradation, clear error messages. Already partially implemented (Sprint 8), but must be bulletproof for launch. |

### P1 -- Target for v1.1 (post-launch, high impact)

| Feature | Rationale |
|---|---|
| **Crossfade** | play:Sub and Symfonium support it. Natural companion to gapless playback. Users expect the option even if they leave it off. |
| **Siri / Shortcuts integration** | Amperfy has full Siri + App Intents support. Apple ecosystem users expect voice control. High polish factor. |
| **Podcast support** | play:Sub, Amperfy, and SubStreamer all support podcasts from Subsonic servers. Expands use cases and session time. |
| **Sleep timer** | Low effort, high utility. Multiple competitors include it. Essential for bedtime listening. |
| **Replay gain** | play:Sub and Amperfy support it. Prevents volume spikes when shuffling across albums. Important for the "shuffle everything" use case. |

### P2 -- Future Releases (differentiation + long tail)

| Feature | Rationale |
|---|---|
| **Chromecast / AirPlay 2 output** | play:Sub supports Chromecast + Jukebox; Symfonium supports Chromecast + UPnP/DLNA + Sonos. Expands Veydrune beyond headphone/speaker playback. |
| **Smart playlists / auto-mixes** | Symfonium's dynamic playlist engine is a major differentiator. Building something similar on iOS would be unique. |
| **Wear OS / Apple Watch companion** | No iOS Subsonic client has an Apple Watch app. First-mover opportunity. |
| **Widget support** | Lock screen and home screen widgets for now playing, quick actions. Modern iOS expectation. |
| **Additional server support (Jellyfin, Plex)** | Symfonium's universal server support is its biggest draw. Expanding beyond Subsonic opens Veydrune to a much larger audience. |
| **Open source consideration** | Amperfy and iSub are both GPLv3. Open sourcing (or offering a source-available license) could build community trust and attract contributors. Worth evaluating post-v1.0 based on business model. |
| **Hi-res audio (24-bit/192kHz)** | play:Sub supports it. Niche but valued by audiophiles who specifically chose self-hosting for lossless playback. |
| **Crossfade visualizer modes** | Leverage the existing Metal shader infrastructure to create reactive visualizer modes that respond to audio frequency data. No competitor has this on iOS. |

---

## 6. Summary

Veydrune enters a market with one strong incumbent (play:Sub), one fast-moving open-source competitor (Amperfy), and several stagnant or minimal alternatives. The opportunity is clear:

- **SwiftUI-native is uncontested.** No competitor builds with SwiftUI. This is Veydrune's structural advantage for both iOS and macOS.
- **macOS is wide open.** Only Amperfy (Catalyst) exists. A native SwiftUI Mac app is a genuine gap in the market.
- **CarPlay + visualizer + modern UI** is a combination no one else offers.

The primary risk is launching without gapless playback, which would immediately position Veydrune as "nice-looking but incomplete" in community reviews. Closing the gapless + EQ + scrobbling gaps before v1.0 transforms Veydrune from "promising" to "competitive," and the SwiftUI + Metal differentiators do the rest.

---

## Sources

- [play:Sub - App Store](https://apps.apple.com/us/app/play-sub-music-streamer/id955329386)
- [play:Sub - Developer Site](https://michaelsapps.dk/playsubapp/)
- [Amperfy - GitHub](https://github.com/BLeeEZ/amperfy)
- [Amperfy - App Store](https://apps.apple.com/us/app/amperfy-music/id1530145038)
- [Amperfy Releases](https://github.com/BLeeEZ/amperfy/releases)
- [SubStreamer - Developer Site](https://substreamerapp.com/)
- [SubStreamer - App Store](https://apps.apple.com/us/app/substreamer/id1012991665)
- [iSub - Official Site](https://isub.app/)
- [iSub - GitHub](https://github.com/einsteinx2/iSubMusicStreamer)
- [iSub - App Store](https://apps.apple.com/us/app/isub-music-streamer/id362920532)
- [Symfonium - Official Site](https://symfonium.app/)
- [Symfonium - Google Play](https://play.google.com/store/apps/details?id=app.symfonik.music.player)
- [Navidrome Client Apps](https://www.navidrome.org/apps/)
