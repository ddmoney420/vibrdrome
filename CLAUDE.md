# Vibrdrome - Claude Code Context

## Repository Overview

**Vibrdrome** is a native iOS/macOS/watchOS music player for Navidrome (Subsonic API).

- **Stack**: Swift 6, SwiftUI, SwiftData, AVPlayer, CarPlay, WatchConnectivity
- **Build**: XcodeGen → Xcode 26.4, iOS 17.0+, macOS 14.0+, watchOS 11.0+
- **Simulator**: iPhone 17 Pro, Apple Watch Series 11 (46mm)
- **Targets**: Vibrdrome (iOS/macOS), VibrdromeWidget, VibrdromeWatch

## Quick Reference

```bash
# Build iOS
xcodebuild -project Vibrdrome.xcodeproj -scheme Vibrdrome \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet build

# Build macOS
xcodebuild -project Vibrdrome.xcodeproj -scheme VibrdromeMac \
  -destination 'platform=macOS' -quiet build

# Build watchOS
xcodebuild -project Vibrdrome.xcodeproj -scheme VibrdromeWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' -quiet build

# Run unit tests
xcodebuild -project Vibrdrome.xcodeproj -scheme Vibrdrome \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:VibrdromeTests test

# SwiftLint
swiftlint

# Regenerate Xcode project (ALWAYS restore entitlements after!)
xcodegen generate
```

## CI / Build Policy

**This is a PRIVATE repo. GitHub Actions CI costs real money (macOS runners use 10x billing multiplier).**

- **ALWAYS build and test locally** before pushing
- **Do NOT rely on GitHub Actions CI** — run builds and tests on this machine
- **Batch commits** when possible to minimize CI triggers
- **Website-only changes** (docs/ folder) do not need CI — consider skipping CI with `[skip ci]` in commit message when only docs change
- Before pushing, ask: "Does this need CI, or can I verify locally?"
- **ALWAYS run SwiftLint before committing** — zero violations required
- **Branching**: `main` is protected. All work goes on `develop`. Merge to `main` via PR only.
  - `main` requires: PR + CI passing (SwiftLint + Build iOS). No direct pushes.
  - `develop` is the daily working branch. Commit freely here.
  - Release flow: finish work on `develop` -> create PR to `main` -> CI passes -> merge -> archive and upload to TestFlight.
  - Hotfixes: `enforce_admins` is off, so repo owner can bypass protection in emergencies.
  - Tag each release: `v1.0.0-beta.39`, etc.
- **Never send messages to external people** without explicit user review and approval

## Pre-TestFlight Checklist

Run in order before every TestFlight build. Every step is mandatory -- no "if applicable", no "if new features", no skipping.

1. `swiftlint` -- 0 violations
2. Unit tests: `xcodebuild test -only-testing:VibrdromeTests` -- all pass
3. UI tests: `xcodebuild test -only-testing:VibrdromeUITests/RotationTests` -- all pass
4. Security audit on recent changes
5. Build iOS with 0 warnings
6. Build macOS with 0 warnings
7. Build watchOS with 0 warnings
8. Device test on phone (see TESTING.md for full regression checklist)
9. Update `CHANGELOG.md` -- new build entry, no exceptions
10. Update `docs/changelog.html` -- matching HTML entry, no exceptions
11. Update `docs/features.html` -- add or refresh any feature text that changed; if nothing changed, verify by re-reading
12. Update `docs/index.html` feature grid -- same rule as features.html
13. Update `docs/User-Guide.md` -- add or refresh any user-facing behavior that changed
14. Update `docs/TESTING-CHECKLIST.md` -- add test items for every user-visible change
15. Update `docs/APPSTORE-METADATA.md` "What's New" block for the new build, and refresh any description lines the build affects
16. Update `TESTING.md` -- test items for every new feature and regression area
17. Increment `CURRENT_PROJECT_VERSION` in `project.yml` (all 3 targets)
18. Regenerate xcodegen and restore entitlements

The pre-commit hook (`scripts/hooks/pre-commit`) enforces steps 9-16: if `project.yml`'s `CURRENT_PROJECT_VERSION` bumps in a commit, the required doc files must be touched in the same commit. Do not bypass with `--no-verify`; the hook is the safety net.

## Post-XcodeGen Entitlements Restore

`xcodegen generate` clears entitlements. ALWAYS restore both files after:

**Vibrdrome/Vibrdrome.entitlements** — needs:
- `com.apple.developer.carplay-audio` = true
- `com.apple.security.application-groups` = ["group.com.vibrdrome.app"]

**VibrdromeWidget/VibrdromeWidget.entitlements** — needs:
- `com.apple.security.application-groups` = ["group.com.vibrdrome.app"]

## Key Patterns

- `xcodegen` clears entitlements — must restore CarPlay + App Groups entitlements after (see above)
- Swift extensions can't access private — use internal or accessor methods
- Song is a value type — track mutable state via `@State`
- Subsonic JSON arrays may be omitted (not empty) — always `[T]?`
- DO NOT loop on test runs — run once, report results, stop
- `#if os(macOS)` for Discord RPC, `#if os(iOS)` for WatchSessionManager, AirPlayButton, Haptics
- Watch app communicates via WatchConnectivity — iPhone side is in `WatchSessionManager.swift`
- `SubsonicClientProvider.shared.client` must be set when AppState configures credentials (for watch commands)
- EQ tap uses pre-gain attenuation to prevent clipping — don't remove the `preGain` logic in EQTapProcessor
- ReplayGain capped at 1.5x (+3.5dB) to prevent clipping on hot masters
