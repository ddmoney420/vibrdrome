# Release Documentation Index

**App:** Veydrune — iOS/macOS Music Player for Navidrome
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

---

## Top 10 Risks

1. **No CarPlay entitlement from Apple** — Cannot ship CarPlay without MFi approval (weeks-to-months lead time)
2. **Low test coverage (~10%)** — Only models/auth/utilities tested; core audio, networking, downloads untested
3. **No real-device testing** — All development on simulator; unknown device-specific issues
4. **No TestFlight beta** — Zero external users have tested the app
5. **No app icon image** — AppIcon asset catalog has no actual PNG; will be rejected by App Store
6. **No screenshots captured** — Required for App Store listing
7. **No privacy policy URL** — Required field in App Store Connect
8. **No gapless playback** — Table-stakes feature for music players; competitors all have it
9. **No crash reporting** — No Sentry/Crashlytics means blind to production crashes
10. **No analytics** — Cannot measure retention, usage patterns, or feature adoption

---

## Top 10 Quick Wins

1. **Create app icon** — Design 1024x1024 PNG, add to AppIcon.appiconset
2. **Host privacy policy** — Simple static page: "No data collected, all local"
3. **Capture screenshots** — Run on simulator, capture 6-10 screens per device class
4. **Apply for CarPlay entitlement** — Start the Apple approval process now (long lead time)
5. **Enable crash reporting** — Add lightweight crash reporter (MetricKit or Firebase Crashlytics)
6. **Register Apple Developer account** — Required for any distribution
7. **TestFlight build** — Get the app into testers' hands ASAP
8. **Add gapless playback** — Use AVQueuePlayer to preload next track
9. **Remove `|| true` from CI test step** — Tests are passing; CI should fail on test failures
10. **Add code coverage to CI** — Track coverage trends with each PR

---

## Readiness Assessment

### Ready for TestFlight?
**Yes, with caveats.** The app builds clean, has 96 passing tests, comprehensive error handling, VoiceOver accessibility, and offline download support. The main blocker is signing — an Apple Developer account and provisioning profiles are needed. An app icon is also needed.

### Ready for App Store?
**Not yet.** Key blockers:
- CarPlay entitlement (must be approved by Apple)
- App icon (no image in asset catalog)
- Privacy policy URL (required)
- Screenshots (required)
- Real-device testing not done
- No beta testing feedback

### Estimated Time to App Store Submission
- **2-4 weeks** for technical preparation (icon, screenshots, privacy policy, signing, TestFlight)
- **4-8 weeks** for CarPlay entitlement approval (unpredictable, Apple-dependent)
- **1-2 weeks** for beta testing and iteration

---

## Project Statistics

| Metric | Value |
|--------|-------|
| Swift files | 65+ |
| Lines of code | ~11,000 |
| SPM dependencies | 2 (NukeUI, KeychainAccess) |
| Test suites | 5 |
| Unit tests | 96 (all passing) |
| SwiftLint warnings | 25 |
| SwiftLint errors | 0 |
| Build warnings | 0 |
| Platforms | iOS 17+, macOS 14+ |
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
9. Implement gapless playback (P0 feature gap)
10. Submit to App Store
