# 04 — Testing Status

## Current State

| Metric | Value |
|--------|-------|
| Test target | VeydruneTests (added Sprint 3) |
| Test framework | Swift Testing (`@Test`, `#expect`) |
| Total tests | 96 |
| Passing | 96 |
| Failing | 0 |
| Test suites | 5 |
| Build verification | iOS + macOS pass clean |

## Test Suites

### SubsonicModelsTests — 55 tests
Tests JSON decoding for all Subsonic API model types.

**Coverage:**
- Song: minimal, full, empty strings, identifiable
- Album: with/without songs, minimal, omitted arrays
- Artist: with/without albums
- Playlist: `isPublic` CodingKey mapping, with/without entries
- SearchResult3: all present, all omitted, mixed
- Genre: basic, minimal
- InternetRadioStation: with/without homepage
- PlayQueue: with entries, empty
- Bookmark: with/without comment and entry
- LyricsList: synced, unsynced, empty, identifiable lines
- SubsonicResponse: hyphenated key, ok/error status, empty payload, payload variants
- Wrapper types: all tested for presence and omission
- Edge cases: large integers, Unicode, API error object, ReplayGain

### SubsonicAuthTests — 10 tests
Tests authentication parameter generation.

**Coverage:**
- Required query parameters present (u, t, s, v, c, f)
- Username, format, client name, API version values
- MD5 token format (32 hex chars)
- Salt randomization between calls
- Salt alphanumeric character set
- Different passwords produce different tokens
- Password never appears in raw parameters

### FormatDurationTests — 9 tests
Tests the `formatDuration()` utility functions.

**Coverage:**
- Zero, single digits, minutes, hours
- Hour boundary (3599 → 59:59, 3600 → 1:00:00)
- Large values, TimeInterval decimals
- Negative input behavior documented

### StringSanitizedTests — 9 tests
Tests `String.sanitizedFileName` extension.

**Coverage:**
- Normal strings, all illegal characters
- Forward/back slashes, colons, asterisks, etc.
- Leading/trailing whitespace trimming
- Unicode preservation, empty string, mixed content

### ErrorPresenterTests — 11 tests
Tests `ErrorPresenter.userMessage(for:)` mapping.

**Coverage:**
- SubsonicError cases: auth (code 40), not found (70), permission (50), HTTP 401, HTTP 500
- Network errors: no server, unavailable, invalid URL
- URLError: timeout, no internet
- Unknown error fallback

## What's NOT Tested

### No Unit Tests Yet
- **AudioEngine queue logic** — Complex queue management (add, remove, move, next, previous, shuffle, repeat modes). These are pure logic methods that don't require AVPlayer, making them ideal candidates for testing.
- **SubsonicClient** — Network layer. Requires mock URLSession or protocol abstraction.
- **DownloadManager** — Requires mock URLSession delegate, SwiftData context.
- **AppState** — Credential loading, server management. Requires mock Keychain.
- **CarPlayManager** — Requires CPTemplate mocking (Apple framework).
- **NowPlayingManager** — MPNowPlayingInfoCenter integration.

### No Integration/UI Tests
- No XCUITest target
- No snapshot tests
- No CarPlay simulator automation

## Running Tests

```bash
make test                # Run via Makefile
# Or directly:
xcodebuild test \
  -project Veydrune.xcodeproj \
  -scheme Veydrune \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

## Test Configuration

- **project.yml**: `VeydruneTests` target with `bundle.unit-test` type
- **Scheme**: Veydrune scheme includes VeydruneTests in test action
- **Dependencies**: Tests link against main Veydrune target via `@testable import`
- **Framework**: Swift Testing (modern `@Test` + `#expect`, not XCTest)
