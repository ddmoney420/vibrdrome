# Changelog

All notable changes to Vibrdrome (iOS/macOS) are documented here.

## v1.0.0

### Build 13 — April 2, 2026
- Fix CarPlay logout when connecting (Keychain accessibility change)

### Build 12 — March 31, 2026
- Allow HTTP connections to non-local servers (DuckDNS, dynamic DNS)
- Security warning shown for HTTP URLs recommending HTTPS

### Build 11 — March 31, 2026
- Fix lock screen showing 15-second skip buttons instead of previous/next track

### Build 10 — March 31, 2026
- Library folder switching for multi-library Navidrome servers
- musicFolderId support added to album list, search, starred, and random songs API calls

### Build 9 — March 31, 2026
- Fix CarPlay crash caused by CPSearchTemplate in tab bar
- Search moved to Library > Search in CarPlay

### Build 8 — March 30, 2026
- Radio station favicons from homepage domain and radio-browser.info
- CarPlay threading improvements (@MainActor on scene delegate and search handler)

### Build 7 — March 30, 2026
- CarPlay audio entitlement enabled

### Build 6 — March 29, 2026
- Customizable Library layout (show/hide/reorder pills and carousels)
- 6 new visualizer presets: Lava Lamp, Starfield, Ripple, Fireflies, Prism, Ocean (18 total)
- Smoother visualizer audio reactivity (reduced FFT gain, lower smoothing factor, lerp interpolation)
- Photosensitivity warning on first visualizer launch with "Don't Show Again" option
- Disable Visualizer toggle in Settings > Accessibility
- Epilepsy notice and prefers-reduced-motion CSS on website

### Build 5 — March 28, 2026
- Fix device rotation dismissing player, visualizer, and lyrics views
- Move fullScreenCover for NowPlayingView to ContentView for rotation stability
- Lift showNowPlaying, showVisualizer, showLyrics state to AppState
- Remove unused Metal shader variable
- Rotation UI tests verifying player/visualizer/lyrics stay open

### Build 4 — March 20, 2026
- Audio-reactive visualizer with FFT spectrum analysis
- 12 Metal shader presets
- Library quick access pills and carousels

### Build 3 — March 19, 2026
- Bug fixes and stability improvements

### Build 2 — March 19, 2026
- Initial feature set

### Build 1 — March 18, 2026
- Initial TestFlight release
