# Privacy Policy for Vibrdrome

**Last updated: June 4, 2026**

## Overview

Vibrdrome is a music player app for iOS, macOS, and Android that connects to your personal Navidrome or Subsonic-compatible media server. Your privacy is important to us. This policy explains what data Vibrdrome accesses and how it is handled.

## Data Collection

**Vibrdrome does not collect, store, or transmit any personal data to us.** We have no servers, no analytics, and no tracking.

## Data Stored on Your Device

Vibrdrome stores the following data locally on your device:

- **Server credentials** (URL, username, password) — stored securely in the iOS/macOS Keychain or Android Keystore
- **Music cache** — downloaded songs stored in the app's sandboxed container
- **Playback history and preferences** — stored locally using SwiftData
- **Settings** (theme, equalizer presets, bitrate preferences) — stored in UserDefaults

This data stays on your device except when communicating with your configured media server and when you use the optional internet features described in **External Services and Data Flows** below.

## Network Communication

Vibrdrome's core features communicate directly with the **Navidrome/Subsonic server you configure** — to authenticate, browse your library, stream music, and sync favorites/playlists, using the server URL you set. In addition, several **optional** features can contact third-party services, listed under **External Services and Data Flows** below.

Your Navidrome/Subsonic credentials are used only to connect to the media server you configure. They are **not** sent to LRCLIB, Last.fm, ListenBrainz, Discord, DuckDuckGo, radio-browser, or external artist-link services.

## External Services and Data Flows

Beyond your own media server, Vibrdrome can contact the third-party services below. Each entry states what is sent, to whom, whether it is optional, and how you control it. Vibrdrome has no servers of its own and never receives this data; it goes directly from your device to the service.

- **Your media server (required)** — all browsing, streaming, authentication, and favorites/playlist sync go to the Navidrome/Subsonic server URL you configure.
- **Internet lyrics — LRCLIB (optional, on by default)** — when your server has no lyrics for a track, the track's title, artist, album, and duration are sent to lrclib.net. Control: Settings → Player → "Fetch Lyrics from the Internet."
- **Last.fm scrobbling (optional, off until you connect it)** — if enabled, Vibrdrome sends listening activity such as track, artist, album, and playback time to Last.fm (ws.audioscrobbler.com) using the account credentials or API settings you provide. Control: Settings → Player → Last.fm.
- **ListenBrainz scrobbling (optional, off until you connect it)** — if you provide a ListenBrainz token, Vibrdrome sends that token and your listens to api.listenbrainz.org. Control: Settings → Player → ListenBrainz.
- **Discord Rich Presence (macOS only, optional, off by default)** — when enabled, Vibrdrome shares the current track, artist, album, and play state with the Discord app running on your Mac, which can display it on your Discord profile. Control: Settings → Player → Discord Rich Presence.
- **Internet radio search — radio-browser.info (optional)** — when you search for internet radio stations with "Find Stations," your search query (station name or genre) is sent to radio-browser.info.
- **Internet radio station icons — DuckDuckGo (automatic while browsing radio)** — to display a station's icon, the station's website domain is sent to DuckDuckGo's favicon service (icons.duckduckgo.com).
- **External artist links (optional, only when you tap one)** — tapping an artist link opens a search for that artist's name (MusicBrainz, Last.fm, Wikipedia, and Google by default, or any custom link you add) in your browser; the artist's name is sent to that site as part of the URL.

## Third-Party Services

Vibrdrome does not integrate any third-party analytics, advertising, or tracking services, and does not send crash or diagnostic data to any third party — diagnostics, when captured, stay on your device. The optional features listed under **External Services and Data Flows** use third-party services to provide that functionality.

## Data Sharing

The developer does not collect, receive, share, or sell your data — Vibrdrome has no servers, analytics, or tracking. When you enable the optional features above, the app transmits the data described there directly to the third-party services you choose, at your direction; the developer is not involved in and does not receive that data.

## Children's Privacy

Vibrdrome does not knowingly collect any information from children under 13 years of age.

## Changes to This Policy

If we update this privacy policy, the changes will be posted here with an updated date.

## Contact

If you have questions about this privacy policy, please open an issue at:
https://github.com/ddmoney420/vibrdrome/issues
