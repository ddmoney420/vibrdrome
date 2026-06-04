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

**This is a PUBLIC repo, so GitHub Actions is free (no minutes cap / billing).** The reason to verify locally is *speed and reliability*, not cost: don't wait on the cloud to learn something a local run tells you in minutes.

**Two distinct "CI"s — don't confuse them:**
- **Local `scripts/verify-build.sh`** = our real QA loop. SwiftLint + iOS/macOS/watchOS builds + tests, one `RESULT: PASS|FAIL`. This is the source of truth for "is it green." Run it before every commit/push.
- **Cloud GitHub Actions** (`.github/workflows/ci.yml`) = a *merge gate* `main`'s branch protection enforces. A PR to `main` cannot merge until the required **`SwiftLint`** and **`Build iOS`** check runs report success. The local run does NOT satisfy this — GitHub only accepts its own check runs.

- **ALWAYS build and test locally** (`verify-build.sh`) before pushing — faster feedback than the cloud
- **`[skip ci]` caveat:** NEVER put `[skip ci]` on a commit that will become the head of a PR to `main`. It skips the workflow, so the required `SwiftLint`/`Build iOS` checks never register and the PR is stuck BLOCKED. (Also: an *empty* commit does not reliably re-trigger Actions — push a real change to re-fire CI.) `[skip ci]` is only safe on commits that stay on `develop` and won't head a `main` PR.
- **ALWAYS run SwiftLint before committing** — zero violations required
- **ALWAYS run SwiftLint before committing** — zero violations required
- **Branching**: `main` is protected. All work goes on `develop`. Merge to `main` via PR only.
  - `main` requires: PR + CI passing (SwiftLint + Build iOS). No direct pushes.
  - `develop` is the daily working branch. Commit freely here.
  - Release flow: finish work on `develop` -> create PR to `main` -> CI passes -> merge -> archive and upload to TestFlight.
  - Hotfixes: `enforce_admins` is off, so repo owner can bypass protection in emergencies.
  - Tag each release: `v1.0.0-beta.39`, etc.
- **Never send messages to external people** without explicit user review and approval

## Verification Discipline (guardrails)

These rules exist because scrolled `xcodebuild`/test output is easy to misread (and some terminals render it truncated or garbled). "Verified" must mean a deterministic artifact, not an eyeballed scroll.

1. **One source of truth for green:** run `scripts/verify-build.sh` (or `--quick` for SwiftLint + iOS build + unit tests). Report its **exit code / `RESULT: PASS|FAIL`** line — never claim a build or test passed from scrolled output. Per-check logs land in `build-logs/`.
2. **Capture, then grep:** when running a build/test by hand, redirect to a file (`> /tmp/x.log 2>&1`) and grep the file for `BUILD SUCCEEDED`, `\.swift:.*: error:`, `\.swift:.*: warning:`, `TEST SUCCEEDED/FAILED`. Do not infer pass/fail from what scrolled past.
3. **Zero warnings means zero:** a build with any `*.swift:line:col: warning:` is NOT green, even if it "succeeded". The tooling-noise lines (`appintentsmetadataprocessor`, `SSU artifacts`) are not source warnings — match on the `*.swift:line:col:` form.
4. **Trust primary evidence, not reports:** subagent summaries, `WebFetch` answers, and prior assistant claims are leads to confirm, not facts. Before stating a finding (especially in code, a commit, or anything user-facing), confirm it directly — Read the file, grep the symbol, run the script.
5. **Confirm tooling exists first:** this can be a fresh machine. If a CLI tool errors as "not found", check `command -v <tool>` and install via brew before proceeding — don't assume the toolchain is present.
6. **If you reported something wrong, retract it explicitly** and re-verify from a clean artifact rather than papering over it.

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
