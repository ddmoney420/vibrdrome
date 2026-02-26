```
______  _____  _      _____   ___   _____  _____
| ___ \|  ___|| |    |  ___| / _ \ /  ___||  ___|
| |_/ /| |__  | |    | |__  / /_\ \\ `--. | |__
|    / |  __| | |    |  __| |  _  | `--. \|  __|
| |\ \ | |___ | |____| |___ | | | |/\__/ /| |___
\_| \_|\____/ \_____/\____/ \_| |_/\____/ \____/
```

# Release Documentation Index

**App:** Vibrdrome -- iOS/macOS Music Player for Navidrome ♪♫(◕‿◕)♫♪
**Version:** 1.0.0
**Date:** February 2026

---

## Documents

| # | Document | Description |
|---|----------|-------------|
| 00 | [Repo Map](00-repo-map.md) | Targets, schemes, deps, entitlements, plists, directory structure |
| 01 | [Build](01-build.md) | Exact build steps, tool versions, XcodeGen workflow |
| 02 | [Bug Hunt](02-bug-hunt.md) | All findings: severity, file, snippet, fix status |
| 03 | [Linting](03-linting.md) | SwiftLint rules, baseline, quality gates |
| 04 | [Testing Status](04-testing-status.md) | 96 tests in 5 suites, all passing |
| 05 | [Test Plan](05-test-plan.md) | Future test additions, mock server plan |
| 06 | [App Store Readiness](06-appstore-readiness.md) | Submission checklist, metadata, review notes |
| 07 | [Release Scorecard](07-release-scorecard.md) | 25+ criteria pass/fail, readiness recommendation |
| 08 | [Market Survey](08-market-survey.md) | Competitor comparison, differentiators, roadmap |
| 09 | [User Testing Plan](09-user-testing-plan.md) | Device testing, CarPlay, checklist, bug template |
| 10 | [Offline Playlists Acceptance](10-offline-playlists-acceptance.md) | Offline playlist download, metadata, acceptance criteria |
| 11 | [Artist Radio Spec](11-artist-radio-spec.md) | Continuous auto-play from artist/track seed |
| 12 | [Gapless Playback Spec](12-gapless-playback-spec.md) | AVQueuePlayer lookahead, auto-advance, edge cases |
| 13 | [User Testing Guide](13-user-testing-guide.md) | Feature walkthrough, step-by-step testing for every feature |

---

## Top 10 Risks

1. **No CarPlay entitlement from Apple** -- Cannot ship CarPlay without MFi approval (weeks-to-months lead time)
2. **Low test coverage (~10%)** -- Only models/auth/utilities tested; core audio, networking, downloads untested
3. **No real-device testing** -- All development on simulator; unknown device-specific issues
4. **No TestFlight beta** -- Zero external users have tested the app
5. **No app icon image** -- AppIcon asset catalog has no actual PNG; will be rejected by App Store
6. **No screenshots captured** -- Required for App Store listing
7. **No privacy policy URL** -- Required field in App Store Connect
8. **No crash reporting** -- No Sentry/Crashlytics means blind to production crashes
9. **No analytics** -- Cannot measure retention, usage patterns, or feature adoption
10. ~~EQ only for downloaded tracks~~ -- **FIXED:** EQ now works for all tracks (streams buffered to temp file)

---

## Top 10 Quick Wins (ﾉ◕ヮ◕)ﾉ*:・゚✧

1. **Create app icon** -- Design 1024x1024 PNG, add to AppIcon.appiconset
2. **Host privacy policy** -- Simple static page: "No data collected, all local"
3. **Capture screenshots** -- Run on simulator, capture 6-10 screens per device class
4. **Apply for CarPlay entitlement** -- Start the Apple approval process now (long lead time)
5. **Enable crash reporting** -- Add lightweight crash reporter (MetricKit or Firebase Crashlytics)
6. **Register Apple Developer account** -- Required for any distribution
7. **TestFlight build** -- Get the app into testers' hands ASAP
8. **Remove `|| true` from CI test step** -- Tests are passing; CI should fail on test failures
9. **Add code coverage to CI** -- Track coverage trends with each PR
10. **Create export logs feature** -- OSLogStore + rolling log file for TestFlight triage

---

## Readiness Assessment

### Ready for TestFlight?
**Yes, with caveats.** The app builds clean, has 96 passing tests, comprehensive error handling, VoiceOver accessibility, and offline download support. The main blocker is signing -- an Apple Developer account and provisioning profiles are needed. An app icon is also needed.

### Ready for App Store?
**Not yet.** Key blockers:
- CarPlay entitlement (must be approved by Apple)
- App icon (no image in asset catalog)
- Privacy policy URL (required)
- Screenshots (required)
- Real-device testing not done
- No beta testing feedback

---

## Project Statistics (⌐■_■)

| Metric | Value |
|--------|-------|
| Swift files | 79 |
| Lines of code | ~14,500 |
| SPM dependencies | 2 (NukeUI, KeychainAccess) |
| Test suites | 5 |
| Unit tests | 96 (all passing) |
| SwiftLint warnings | 0 |
| SwiftLint errors | 0 |
| Build warnings | 0 |
| Platforms | iOS 17+, macOS 14+ |
| Playback modes | 3 (Gapless, Crossfade, EQ) |
| CarPlay | Full CPTemplate integration |
| Accessibility | VoiceOver labels on all controls |

---

## Next Steps (Priority Order)

1. Create app icon (blocks App Store submission)
2. Register Apple Developer account
3. Apply for CarPlay entitlement
4. Generate signing certificates + provisioning profiles
5. Host privacy policy at a public URL
6. Create TestFlight build
7. Capture screenshots for all device sizes
8. Begin beta testing with 5-10 users
9. Real-device playback testing (gapless, crossfade, EQ)
10. Submit to App Store

✧･ﾟ:*✧･ﾟ:*
