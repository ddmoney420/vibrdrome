# Contributing to Vibrdrome (iOS/macOS)

Thanks for your interest in contributing! Whether it's a bug fix, new feature, or documentation improvement, all contributions are welcome.

## Getting Started

```bash
# Prerequisites: Xcode 16+, XcodeGen
brew install xcodegen

# Clone and build
git clone https://github.com/ddmoney420/vibrdrome.git
cd vibrdrome
git checkout develop
xcodegen generate
open Vibrdrome.xcodeproj
```

After `xcodegen generate`, you'll need to configure signing (see below).

### Signing, Bundle ID, and Entitlements

The repo's bundle IDs (`com.vibrdrome.app`, `com.vibrdrome.app.widget`, `com.vibrdrome.app.watchkitapp`) and the CarPlay / App Groups entitlements are all tied to the maintainer's Apple Developer account. To run on your own phone, you'll need to rewrite these locally. **Keep these changes in your fork only -- do not commit them.**

**1. Change the bundle IDs** in `project.yml` to something under your own identifier prefix:

- Line 3: `bundleIdPrefix: com.yourname`
- `PRODUCT_BUNDLE_IDENTIFIER: com.yourname.vibrdrome`
- `PRODUCT_BUNDLE_IDENTIFIER: com.yourname.vibrdrome.widget`
- `PRODUCT_BUNDLE_IDENTIFIER: com.yourname.vibrdrome.watchkitapp`

**2. Remove or replace entitlements** you don't have approval for:

- In `project.yml`, remove `CARPLAY_ENABLED` from the `SWIFT_ACTIVE_COMPILATION_CONDITIONS` line so CarPlay code stops compiling.
- In `Vibrdrome/Vibrdrome.entitlements`, remove the `com.apple.developer.carplay-audio` key (CarPlay audio requires Apple's explicit per-account approval).
- In both `Vibrdrome/Vibrdrome.entitlements` and `VibrdromeWidget/VibrdromeWidget.entitlements`, either remove the `com.apple.security.application-groups` array or change the group ID to one you register under your own team. Without App Groups, the widget won't share playback state with the app but everything else works.

**3. Regenerate the Xcode project** to pick up the `project.yml` changes:

```bash
xcodegen generate
```

**4. Set your Team** in Xcode. Open the project, click the project name at the top of the file tree, and for each target (Vibrdrome, VibrdromeWidget, VibrdromeWatch) under Signing & Capabilities, pick your personal team. Xcode will handle provisioning automatically.

**5. Build and run.** Plug in your phone, select it as the Run destination, Cmd+R. If Xcode complains about a capability after that, the editor will tell you which one -- just remove it.

### Requirements

- Xcode 16+ (Swift 6.0)
- iOS 17.0+ / macOS 14.0+ / watchOS 11.0+
- A Navidrome or Subsonic-compatible server for testing

### Dependencies

Only 2 SPM packages (resolved automatically on first build):
- NukeUI (image loading)
- KeychainAccess (credential storage)

## Branch Workflow

`main` is protected. All PRs go to `develop`.

```
develop  <-- your PR goes here
  |
main     <-- releases only, requires CI to pass
```

1. Fork the repo
2. Branch from `develop` (`git checkout -b feature/my-feature develop`)
3. Make your changes
4. Open a PR against `develop`

Do NOT target `main`. It requires CI checks and is merged by the maintainer at release time.

## Before Submitting a PR

1. `swiftlint` with zero violations
2. Build iOS, macOS, and watchOS with 0 warnings
3. Run unit tests: `xcodebuild test -only-testing:VibrdromeTests`
4. New UserDefaults keys go in `UserDefaultsKeys.swift`
5. New settings should use `@AppStorage` with those keys
6. One feature or fix per PR

## Code Style

- Follow existing patterns in the codebase
- Use SwiftUI for all new views
- Use `#if os(iOS)` / `#if os(macOS)` for platform-specific code
- Sensitive credentials go in Keychain, not UserDefaults
- Add accessibility labels to interactive elements
- No force unwraps on optionals from external data
- Keep views small and composable

## Architecture Notes

- `AudioEngine.shared` is the single playback facade. All UI, CarPlay, and remote commands go through it.
- `SubsonicClient` handles all API calls. Never use URLSession directly for API requests.
- `OfflineActionQueue` handles star/unstar/scrobble when offline. Flushes automatically on reconnect.
- CarPlay audio apps can only use `CPTabBarTemplate`, `CPListTemplate`, `CPNowPlayingTemplate`. No `CPSearchTemplate`.
- Song is a value type (struct). Track mutable state via `@State`.
- Subsonic JSON arrays may be omitted (not empty). Always use `[T]?`.

## Project Structure

```
Vibrdrome/
  App/           App entry, AppState, Theme
  CarPlay/       CarPlay scene delegate and template manager
  Core/
    Audio/       AudioEngine (split into 4 files), EQ, crossfade, spectrum
    Constants/   UserDefaultsKeys
    Downloads/   Background download manager, cache
    Networking/  SubsonicClient, API models, Last.fm, ListenBrainz, Discord RPC
    Persistence/ SwiftData models
  Features/      SwiftUI views organized by feature
  Shared/        Reusable components and extensions
```

## Running Tests

```bash
# Unit tests
xcodebuild -project Vibrdrome.xcodeproj -scheme Vibrdrome \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:VibrdromeTests test

# SwiftLint
swiftlint

# Build all platforms
xcodebuild -scheme Vibrdrome -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet build
xcodebuild -scheme VibrdromeMac -destination 'platform=macOS' -quiet build
xcodebuild -scheme VibrdromeWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' -quiet build
```

## Reporting Bugs

Use the GitHub issue templates. Include build number, device/OS version, steps to reproduce, and expected vs actual behavior.

## Security Issues

Do NOT open public issues for security vulnerabilities. Email vibrdrome@gmail.com instead. See SECURITY.md.

## Community

- **Discord:** [Join the server](https://discord.gg/9q5uw3CfN)
- **Email:** vibrdrome@gmail.com
- **Website:** [vibrdrome.io](https://vibrdrome.io)

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
