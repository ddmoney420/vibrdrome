# Vibrdrome - Claude Code Context

## Repository Overview

**Vibrdrome** is a native iOS/macOS/Android music player for Navidrome (Subsonic API).

- **Stack**: Swift 6, SwiftUI, SwiftData, AVPlayer, CarPlay
- **Build**: XcodeGen → Xcode 26.2, iOS 17.0+, macOS 14.0+
- **Simulator**: iPhone 17 Pro

## Quick Reference

```bash
# Build iOS
xcodebuild -project Vibrdrome.xcodeproj -scheme Vibrdrome \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet build

# Build macOS
xcodebuild -project Vibrdrome.xcodeproj -scheme Vibrdrome \
  -destination 'platform=macOS' -quiet build

# Run unit tests
xcodebuild -project Vibrdrome.xcodeproj -scheme VibrdromeTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet test

# SwiftLint
swiftlint
```

## CI / Build Policy

**This is a PRIVATE repo. GitHub Actions CI costs real money (macOS runners use 10x billing multiplier).**

- **ALWAYS build and test locally** before pushing
- **Do NOT rely on GitHub Actions CI** — run builds and tests on this machine
- **Batch commits** when possible to minimize CI triggers
- **Website-only changes** (docs/ folder) do not need CI — consider skipping CI with `[skip ci]` in commit message when only docs change
- Before pushing, ask: "Does this need CI, or can I verify locally?"
- **ALWAYS run unit tests before TestFlight builds** — `xcodebuild test` with VibrdromeTests target
- **ALWAYS run SwiftLint before committing** — zero violations required

## Key Patterns

- `xcodegen` clears entitlements — must restore CarPlay entitlement after
- Swift extensions can't access private — use internal or accessor methods
- Song is a value type — track mutable state via `@State`
- Subsonic JSON arrays may be omitted (not empty) — always `[T]?`
- DO NOT loop on test runs — run once, report results, stop
