# Veydrune Developer Guide

## Prerequisites

- **macOS 14+**
- **Xcode 16+** (with iOS 17.0+ SDK)
- **XcodeGen**: `brew install xcodegen`
- **SwiftLint** (optional, for linting): `brew install swiftlint`

## Build

```bash
# Generate the Xcode project and build for iOS
make generate && make build-ios

# Build for macOS
make generate && make build-macos
```

**Important:** Always use `make generate` instead of running `xcodegen` directly. The Makefile restores the CarPlay entitlement file, which XcodeGen clears on every run.

## Test

```bash
make test
```

Runs 96 unit tests using the Swift Testing framework.

## Lint

```bash
brew install swiftlint
make lint
```

## Architecture Overview

### Singletons

All core singletons are `@Observable` and `@MainActor` for Swift 6 strict concurrency:

| Singleton | Role |
|---|---|
| `AppState.shared` | App-wide state: current server, credentials, user preferences. Loads credentials on init (critical for CarPlay cold launch). |
| `AudioEngine.shared` | AVPlayer-based playback engine. Manages queue, shuffle, repeat, now-playing info, and audio session. Uses a generation counter to discard stale async callbacks. |
| `DownloadManager.shared` | Handles file downloads with progress tracking. Uses `NSLock` for thread safety (`@unchecked Sendable`). Download methods are `@MainActor`. |
| `PersistenceController.shared` | SwiftData `ModelContainer` for offline metadata, bookmarks, and download records. |

### Networking

- `SubsonicClient` -- `@Observable @MainActor Sendable`. Handles all Subsonic/OpenSubsonic API calls with automatic retry logic and an error presenter for surfacing failures to the UI.
- Credentials: password stored in Keychain (via KeychainAccess), URL and username in UserDefaults.

### UI Layer

- **iOS**: `ContentView` uses a `TabView` with Library, Search, Playlists, Downloads, and Settings tabs.
- **macOS**: `MacContentView` uses a `NavigationSplitView` with a sidebar.
- Feature views live in `Features/` (e.g., `Features/Library/`, `Features/Player/`, `Features/Search/`).
- Shared components (reusable views, view modifiers) live in `Shared/`.

### CarPlay

- Implemented via `CPTemplateApplicationScene`.
- `CPTemplate` classes are `@MainActor` in the iOS 26.2 SDK -- closures must be `@MainActor`, not `@Sendable`.
- `CPListSection(items:header:)` requires the `sectionIndexTitle:` parameter in this SDK version.

### Dependencies (SPM)

| Package | Purpose |
|---|---|
| NukeUI | Async image loading with disk caching |
| KeychainAccess | Secure credential storage |

## Key Patterns

### Platform-Specific Code

Use `#if os(iOS)` and `#if os(macOS)` for platform differences:

```swift
#if os(iOS)
.navigationBarTitleDisplayMode(.inline)
#endif
```

iOS-only APIs include `.navigationBarTitleDisplayMode`, `.fullScreenCover`, and `.listStyle(.insetGrouped)`. Use cross-platform toolbar placements like `.cancellationAction`, `.primaryAction`, and `.confirmationAction`.

### Subsonic API Gotchas

- **Arrays may be nil, not empty.** Always declare array fields as `[T]?` in response models.
- **Status check:** Use `body.status != "ok"` (not `== "failed"`).
- **`Text("\(intVar)")`** triggers `LocalizedStringKey` interpolation, adding thousands separators. Use `Text(verbatim: "\(intVar)")` instead.

### Value Types and State

`Song` is a struct (value type). For mutable UI state like a star toggle, use `@State` on the view, not a property on the model.

### Async Safety

- Guard that context is still valid after an `await` (e.g., check the current song ID has not changed).
- Array indices from the UI must be bounds-checked before use.
- `URLSession` temporary files are deleted when the delegate callback returns -- move them synchronously.

### SwiftData

All `@Model` non-optional stored properties need default values for migration compatibility.

### Environment in Sheets

Sheets do not inherit the parent's environment automatically. Pass `.environment(appState)` explicitly.

### MainActor Closure Isolation

Closures inside `@MainActor` class methods inherit MainActor isolation. If a framework calls the closure on a background queue (e.g., `MPMediaItemArtwork` requestHandler), move the closure creation to a free function outside the class.

## Adding a New Feature

1. Create a new directory under `Features/` (e.g., `Features/MyFeature/`).
2. Add your SwiftUI views there.
3. Register the feature's entry point in `ContentView` (iOS) and/or `MacContentView` (macOS).
4. If the feature needs a new Subsonic API call, add it to `SubsonicClient`.
5. Run `make generate` to pick up new files, then build and test.

## CI

GitHub Actions runs on every push and pull request:

1. **Lint** -- SwiftLint check.
2. **Build iOS** -- `make build-ios`.
3. **Build macOS** -- `make build-macos`.
4. **Test** -- `make test` (96 unit tests).
