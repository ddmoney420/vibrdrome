# Privacy Policy for Vibrdrome

**Last updated: February 25, 2026**

## Overview

Vibrdrome is a music player app that connects to your personal Navidrome or Subsonic-compatible media server. Your privacy is important to us. This policy explains what data Vibrdrome accesses and how it is handled.

## Data Collection

**Vibrdrome does not collect, store, or transmit any personal data to us.** We have no servers, no analytics, and no tracking.

## Data Stored on Your Device

Vibrdrome stores the following data locally on your device:

- **Server credentials** (URL, username, password) — stored securely in the iOS/macOS Keychain
- **Music cache** — downloaded songs stored in the app's sandboxed container
- **Playback history and preferences** — stored locally using SwiftData
- **Settings** (theme, equalizer presets, bitrate preferences) — stored in UserDefaults

This data never leaves your device except to communicate directly with your configured media server.

## Network Communication

Vibrdrome communicates only with:

1. **Your Navidrome/Subsonic server** — to authenticate, browse your library, stream music, and sync favorites/playlists. All communication uses the server URL you configure.
2. **radio-browser.info** (optional) — only when you search for internet radio stations using the "Find Stations" feature. No personal data is sent; only search queries (genre, station name).

Vibrdrome does not contact any other servers or third-party services.

## Third-Party Services

Vibrdrome does not integrate any third-party analytics, advertising, crash reporting, or tracking services.

## Data Sharing

We do not share, sell, or transfer any user data to third parties. There is no data to share because we do not collect any.

## Children's Privacy

Vibrdrome does not knowingly collect any information from children under 13 years of age.

## Changes to This Policy

If we update this privacy policy, the changes will be posted here with an updated date.

## Contact

If you have questions about this privacy policy, please open an issue at:
https://github.com/ddmoney420/vibrdrome/issues
