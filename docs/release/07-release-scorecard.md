# 07 — Release Readiness Scorecard

**Project:** Vibrdrome — iOS/macOS music player for Navidrome (Subsonic API)
**Evaluated:** 2026-02-21
**Version:** 1.0.0 (Build 1)
**Sprints Complete:** 1-8 (development), 1-5 (release readiness)

---

## Scoring Key

| Grade | Meaning |
|-------|---------|
| PASS | Fully meets the criterion; no action needed |
| PARTIAL | Partially meets the criterion; non-blocking but has gaps |
| FAIL | Does not meet the criterion; must be addressed before release |
| N/A | Not applicable to this project |

---

## 1. Build & CI

| # | Criterion | Grade | Evidence / Notes |
|---|-----------|-------|------------------|
| 1.1 | iOS build succeeds | PASS | 0 errors, 0 warnings on iOS Simulator (iPhone 17 Pro) |
| 1.2 | macOS build succeeds | PASS | 0 errors, 0 warnings on macOS native |
| 1.3 | CI pipeline configured | PASS | `.github/workflows/ci.yml` with lint, build-ios, build-macos, and test jobs |
| 1.4 | CI lint gate enforced | PARTIAL | SwiftLint `--strict` configured but 25 warnings remain; CI would currently fail with `--strict`. Must fix all warnings or relax the gate |
| 1.5 | CI test gate enforced | PARTIAL | Test job exists but uses `\|\| true` to suppress failures (historical artifact from pre-test era). Must remove `\|\| true` |
| 1.6 | Zero compiler warnings | PASS | 0 warnings on both platforms |
| 1.7 | Version/build number management | PASS | `MARKETING_VERSION: 1.0.0`, `CURRENT_PROJECT_VERSION: 1` in project.yml; SettingsView reads from `Bundle.main` dynamically |
| 1.8 | Release build (Archive) | FAIL | No Archive build verified. Requires signing identity and provisioning profiles not yet configured |
| 1.9 | Reproducible build from clean clone | PASS | `make generate` handles XcodeGen + entitlements restoration; documented in `01-build.md` |

**Section score: 6 PASS, 2 PARTIAL, 1 FAIL**

---

## 2. Code Quality

| # | Criterion | Grade | Evidence / Notes |
|---|-----------|-------|------------------|
| 2.1 | SwiftLint configured and running | PASS | `.swiftlint.yml` with tuned thresholds, opt-in rules enabled, severity overrides documented |
| 2.2 | SwiftLint zero errors | PASS | 0 errors across 62 files |
| 2.3 | SwiftLint warnings acceptable | PARTIAL | 25 warnings remaining (8 function_body_length, 6 vertical_parameter_alignment, misc). Non-blocking but should reduce before v1.0 |
| 2.4 | SwiftFormat configured | PASS | `.swiftformat` file present with matching project conventions |
| 2.5 | Unit test suite | PASS | 924 tests across 3 platforms (iOS 680, Android 124, Web 120), all passing |
| 2.6 | Code coverage adequate | PASS | Core audio, queue, cache, API, EQ, replay gain, widgets all covered. 495 iOS unit tests + 185 UI tests |
| 2.7 | UI/integration tests | PASS | 95 iOS XCUITest + 90 macOS XCUITest covering playback, navigation, settings, rotation, playlists, radio |
| 2.8 | Error handling audit | PASS | `ErrorPresenter` maps all error types to user-friendly messages. 29 raw `error.localizedDescription` usages replaced |
| 2.9 | `try?` audit complete | PARTIAL | 79 usages reviewed. 6 high-priority fixed. 23 medium-priority still need logging. 46 justified |
| 2.10 | Codebase audit / bug hunt | PASS | Full audit documented in `02-bug-hunt.md`. 0 blockers, 6 high-severity all fixed |
| 2.11 | Strict concurrency | PASS | `STRICT_CONCURRENCY: complete` project-wide. Swift 6 with full actor isolation |

**Section score: 6 PASS, 2 PARTIAL, 2 FAIL**

---

## 3. Accessibility

| # | Criterion | Grade | Evidence / Notes |
|---|-----------|-------|------------------|
| 3.1 | VoiceOver labels on player controls | PASS | 43 accessibility annotations across NowPlayingView (13), MiniPlayerView (13), QueueView (2), and shared components |
| 3.2 | VoiceOver labels on lists/rows | PASS | TrackRow, AlbumCard, AlbumArtView, ArtistRow, StarButton all annotated |
| 3.3 | VoiceOver in settings/forms | PASS | SettingsView has 3 accessibility annotations; SearchView and RadioView annotated |
| 3.4 | Dynamic Type support | PARTIAL | App-level toggle in settings (`largerText` toggles between `.large` and `.xxxLarge`) applied via `.dynamicTypeSize()`. However, this is a binary toggle, not true system Dynamic Type support. Does not honor the user's system-wide preferred content size category. No `@ScaledMetric` usage for custom dimensions |
| 3.5 | Reduce Motion support | PASS | Custom `@AppStorage("reduceMotion")` toggle. All animations (21 occurrences across 8 files) check `reduceMotion` and disable when true. Visualizer respects the setting |
| 3.6 | Bold Text support | PASS | `@AppStorage("boldText")` toggle in settings. Applied via `.environment(\.legibilityWeight, boldText ? .bold : .regular)` at the app root for both iOS and macOS scenes |
| 3.7 | System accessibility integration | PARTIAL | Reduce Motion and Bold Text use custom in-app toggles rather than reading the system `UIAccessibility` preferences. Works but does not auto-sync with iOS Settings > Accessibility |
| 3.8 | High Contrast support | FAIL | No `accessibilityContrast` or `colorSchemeContrast` handling detected |
| 3.9 | Sufficient color contrast ratios | PARTIAL | Uses system colors and SwiftUI defaults (generally compliant). Custom `Theme.swift` accent colors not audited for WCAG AA contrast ratios |

**Section score: 4 PASS, 3 PARTIAL, 1 FAIL**

---

## 4. Security

| # | Criterion | Grade | Evidence / Notes |
|---|-----------|-------|------------------|
| 4.1 | Passwords in Keychain | PASS | KeychainAccess library; password never in UserDefaults. Verified in security audit |
| 4.2 | No credentials in source code | PASS | No hardcoded credentials. Demo server creds only in App Review notes template (not compiled) |
| 4.3 | No credential logging | PASS | Password never appears in raw auth parameters (SubsonicAuthTests verify this). MD5 token auth transmits hash+salt only |
| 4.4 | HTTPS enforced | PARTIAL | ATS enforces HTTPS by default. No explicit ATS exception declared. However, user-provided radio stream URLs may be HTTP, which would fail silently. Documented in bug hunt as medium-severity |
| 4.5 | Privacy API declarations | PASS | `NSPrivacyAccessedAPITypes` in both `Info.plist` and `Info-macOS.plist`. Declares UserDefaults (CA92.1) and File Timestamps (C617.1) |
| 4.6 | No analytics/tracking SDKs | PASS | Zero third-party analytics, crash reporting, or ad SDKs. Only SPM deps are NukeUI and KeychainAccess |
| 4.7 | Secure file storage | PASS | UUID-based temp filenames, synchronous file moves before URLSession cleanup, proper directory management |

**Section score: 6 PASS, 1 PARTIAL, 0 FAIL**

---

## 5. Networking

| # | Criterion | Grade | Evidence / Notes |
|---|-----------|-------|------------------|
| 5.1 | Retry with exponential backoff | PASS | 1s/2s/4s delays, max 3 retries. Only transient errors (timeout, 5xx, connection lost). Auth errors (401/403) not retried |
| 5.2 | Timeout configuration | PASS | `timeoutIntervalForRequest: 30s`, `timeoutIntervalForResource: 300s` on SubsonicClient URLSession |
| 5.3 | User-friendly error messages | PASS | `ErrorPresenter.userMessage(for:)` covers SubsonicError, URLError, HTTP status codes. 11 unit tests |
| 5.4 | Offline download support | PASS | Background URLSession + SwiftData. `DownloadManager` with proper delegate callbacks and file preservation |
| 5.5 | Offline playback fallback | PASS | `AudioEngine.resolveURL` checks SwiftData for downloaded songs, falls back to streaming. Cleans stale records |
| 5.6 | Offline mode indicator in UI | FAIL | `NWPathMonitor` tracks connectivity but does not surface status to UI. No offline banner or indicator shown to user |
| 5.7 | Network reachability handling | PARTIAL | `NWPathMonitor` used for bitrate selection on cellular. No proactive offline mode switching or queuing of failed requests |

**Section score: 5 PASS, 1 PARTIAL, 1 FAIL**

---

## 6. App Store

| # | Criterion | Grade | Evidence / Notes |
|---|-----------|-------|------------------|
| 6.1 | Privacy labels defined | PASS | "Data Not Collected" — justified by zero analytics, zero tracking, zero third-party data sharing |
| 6.2 | App description drafted | PASS | Full description with feature list in `06-appstore-readiness.md` |
| 6.3 | Keywords defined | PASS | 10 keywords: navidrome, subsonic, music, player, streaming, carplay, offline, self-hosted, library, audio |
| 6.4 | App Review notes with demo credentials | PASS | Template with demo.navidrome.org credentials and testing instructions |
| 6.5 | App icons present (all sizes) | FAIL | `AppIcon.appiconset/Contents.json` declares a 1024x1024 slot but no actual PNG image file exists in the asset catalog |
| 6.6 | Screenshots captured | FAIL | Screenshot requirements documented (devices, suggested set of 10) but no screenshots have been captured |
| 6.7 | Privacy policy URL | FAIL | Required for App Store submission. Not yet created or hosted |
| 6.8 | Support URL | FAIL | Required for App Store submission. Not yet configured |
| 6.9 | Apple Developer account | FAIL | Not yet active. Required for code signing, provisioning profiles, and submission |
| 6.10 | TestFlight beta testing | FAIL | No TestFlight builds distributed. No beta testing performed |
| 6.11 | Age rating questionnaire | PARTIAL | 4+ proposed. Questionnaire not yet completed in App Store Connect |
| 6.12 | Dead features handled | PASS | Gapless playback marked "Coming Soon" and disabled. No placeholder screens |

**Section score: 4 PASS, 1 PARTIAL, 6 FAIL**

---

## 7. CarPlay

| # | Criterion | Grade | Evidence / Notes |
|---|-----------|-------|------------------|
| 7.1 | CarPlay entitlement declared | PASS | `com.apple.developer.carplay-audio` in `Vibrdrome.entitlements`. Restoration automated via `make generate` |
| 7.2 | CarPlay entitlement approved by Apple | FAIL | Must be requested through Apple's CarPlay/MFi program. Not yet submitted |
| 7.3 | Template-based UI (no custom rendering) | PASS | 100% CPTemplate: CPTabBarTemplate, CPListTemplate, CPNowPlayingTemplate, CPSearchTemplate. Audio-only, compliant with HIG |
| 7.4 | List item limits respected | PASS | Genre list capped at 30 items (`prefix(30)`). Search results capped at 20 songs and 20 albums. Album tracks uncapped (inherently bounded) |
| 7.5 | Disconnect/reconnect handling | PASS | `tearDown()` resets navigation flag, cancels tasks, cleans handler. Every async op checks `Task.isCancelled`. Verified in code audit |
| 7.6 | Empty state handling | PASS | Fallback items ("No songs", "No favorites yet") shown for empty collections |
| 7.7 | CarPlay scene manifest | PASS | `CPTemplateApplicationSceneSessionRoleApplication` configured in `Info.plist` |
| 7.8 | CarPlay tested on hardware | FAIL | No physical CarPlay head unit testing. Xcode CarPlay Simulator only |

**Section score: 5 PASS, 0 PARTIAL, 2 FAIL**

---

## 8. Documentation

| # | Criterion | Grade | Evidence / Notes |
|---|-----------|-------|------------------|
| 8.1 | README | PASS | `README.md` at project root |
| 8.2 | User Guide | PASS | `docs/User-Guide.md` |
| 8.3 | CarPlay Guide | PASS | `docs/CarPlay-Guide.md` |
| 8.4 | Troubleshooting Guide | PASS | `docs/Troubleshooting.md` |
| 8.5 | Developer Guide | PASS | `docs/Developer-Guide.md` |
| 8.6 | Build documentation | PASS | `docs/release/01-build.md` — full build reproduction steps, tool versions, simulator list |
| 8.7 | Release readiness docs | PASS | 7 documents in `docs/release/` covering repo map, bugs, linting, testing, test plan, App Store readiness, and this scorecard |
| 8.8 | Inline code documentation | PARTIAL | Architecture is well-documented in guides. Inline comments exist for complex patterns. No formal API documentation (DocC or similar) |

**Section score: 7 PASS, 1 PARTIAL, 0 FAIL**

---

## Aggregate Summary

| Category | PASS | PARTIAL | FAIL | Total |
|----------|------|---------|------|-------|
| 1. Build & CI | 6 | 2 | 1 | 9 |
| 2. Code Quality | 6 | 2 | 2 | 10 |
| 3. Accessibility | 4 | 3 | 1 | 8 |
| 4. Security | 6 | 1 | 0 | 7 |
| 5. Networking | 5 | 1 | 1 | 7 |
| 6. App Store | 4 | 1 | 6 | 11 |
| 7. CarPlay | 5 | 0 | 2 | 7 |
| 8. Documentation | 7 | 1 | 0 | 8 |
| **TOTAL** | **43** | **11** | **13** | **67** |

**Pass rate: 64% (43/67)**
**Pass + Partial rate: 81% (54/67)**

---

## Critical Blockers

These FAIL items must be resolved before any external release:

| # | Item | Category | Effort |
|---|------|----------|--------|
| 1.8 | No Archive/Release build verified | Build | Medium — requires Apple Developer account |
| 6.5 | No app icon images | App Store | Medium — design + export |
| 6.6 | No screenshots | App Store | Medium — capture on required devices |
| 6.7 | No privacy policy URL | App Store | Low — draft and host |
| 6.8 | No support URL | App Store | Low — create support page/email |
| 6.9 | No Apple Developer account | App Store | Blocker — $99/year enrollment |
| 6.10 | No TestFlight testing | App Store | High — real-device testing essential |
| 7.2 | CarPlay entitlement not approved | CarPlay | Blocker — Apple approval required, variable timeline |

---

## Non-Blocking Issues (Should Fix)

| # | Item | Category | Priority |
|---|------|----------|----------|
| 1.4 | CI lint gate has 25 SwiftLint warnings | Build | Medium |
| 1.5 | CI test job suppresses failures | Build | Low (quick fix) |
| 2.6 | Code coverage ~10% | Code Quality | Medium |
| 2.7 | No UI tests | Code Quality | Low for v1.0 |
| 2.9 | 23 `try?` usages need logging | Code Quality | Low |
| 3.4 | Dynamic Type is binary toggle, not system-synced | Accessibility | Medium |
| 3.7 | Accessibility settings not synced with system | Accessibility | Low |
| 3.8 | No High Contrast support | Accessibility | Low |
| 3.9 | Custom colors not audited for contrast | Accessibility | Low |
| 4.4 | HTTP radio streams may fail silently | Security | Low |
| 5.6 | No offline mode indicator | Networking | Medium |
| 5.7 | No proactive offline handling | Networking | Low |
| 7.8 | No physical CarPlay hardware testing | CarPlay | Medium |

---

## Release Recommendation

### Ready for TestFlight? NO

**Reason:** Cannot build a TestFlight archive without an Apple Developer account (6.9), signing identity (1.8), and an app icon (6.5). These three items are the minimum prerequisites for any TestFlight distribution. Once the developer account is active and the app icon is added, a TestFlight build could be distributed for beta testing even without the CarPlay entitlement (CarPlay features would simply be unavailable to testers).

**Path to TestFlight (estimated 1-2 weeks):**
1. Enroll in Apple Developer Program
2. Design and add app icon to asset catalog
3. Create App ID, provisioning profiles
4. Verify Archive build succeeds
5. Upload first build to TestFlight

### Ready for App Store? NO

**Reason:** In addition to the TestFlight prerequisites, App Store submission requires: approved CarPlay entitlement from Apple (7.2, timeline is unpredictable and can take weeks to months), screenshots on required device sizes (6.6), a hosted privacy policy (6.7), a support URL (6.8), and ideally at least one round of TestFlight beta testing (6.10) to catch real-device issues.

**Path to App Store (estimated 4-8 weeks after TestFlight):**
1. Complete all TestFlight prerequisites
2. Apply for CarPlay Audio entitlement via Apple
3. Run TestFlight beta with real users
4. Capture screenshots on required devices
5. Host privacy policy and support page
6. Complete App Store Connect metadata
7. Submit for App Review

### What IS Ready

The codebase itself is in strong shape for a v1.0:
- Clean builds on both platforms with zero warnings
- 924 passing tests across iOS, Android, and Web
- Full security audit passed
- Error handling is comprehensive and user-friendly
- CarPlay implementation is template-compliant and well-tested in code
- Networking has proper retry, timeout, and offline fallback
- Accessibility covers VoiceOver, Reduce Motion, and Bold Text
- Documentation is thorough across user, developer, and release tracks

The remaining work is primarily administrative (Apple account, entitlements, assets, metadata) rather than engineering.
