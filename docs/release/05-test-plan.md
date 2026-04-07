# 05 — Test Plan

## Priority Test Additions

### P0 — AudioEngine Queue Logic (~20 tests)
**Why:** Complex branching logic with shuffle, repeat modes, and index management. Pure logic, no AVPlayer needed.

**Test cases:**
- `addToQueue` appends to end
- `addToQueueNext` inserts after current index
- `removeFromQueue` removes correct item, guards out-of-bounds
- `moveInQueue` reorders correctly
- `clearQueue` keeps current song, resets index
- `upNext` returns correct slice
- `next()` — sequential (wrap at end with repeat-all, stop at end with repeat-off)
- `next()` — repeat-one (stays on same track)
- `next()` — shuffle (picks different index, stops after queue.count plays)
- `previous()` — sequential (wrap with repeat-all, restart at 0)
- `previous()` — restarts if >3 seconds in (would require mocking currentTime)
- `toggleShuffle` / `cycleRepeatMode`

**Approach:** Create test helper that initializes AudioEngine with a test queue (would need a factory method or test-only init, since AudioEngine is a singleton with private init).

**Blocker:** AudioEngine is a `@MainActor` singleton. Testing requires either:
1. Extract queue logic into a separate `QueueManager` class (preferred)
2. Use `@MainActor` test functions (works but couples tests to singleton)

### P1 — SubsonicClient with Mock URLSession (~15 tests)
**Why:** Network layer is the most critical integration point.

**Approach:**
1. Define `protocol URLSessionProtocol { func data(from: URL) async throws -> (Data, URLResponse) }`
2. Make SubsonicClient accept the protocol
3. Create `MockURLSession` returning fixture data
4. Test all convenience methods with known JSON fixtures
5. Test retry logic with simulated failures

**Test cases:**
- Successful ping returns true
- 401 error sets isConnected = false
- Retry on 500 (verify 3 attempts)
- No retry on 401
- Timeout triggers retry
- All convenience methods decode correctly

### P2 — AppState Credential Management (~10 tests)
**Why:** Critical path — wrong credential handling = can't use app.

**Approach:** Mock Keychain (wrap KeychainAccess behind protocol).

**Test cases:**
- Login stores URL/username in UserDefaults, password in Keychain
- Logout clears all credentials
- Multi-server: add, switch, delete servers
- Server list encode/decode round-trip
- Missing password in Keychain handled gracefully

### P3 — DownloadManager (~10 tests)
**Why:** File operations + SwiftData + background URLSession — many edge cases.

**Approach:** Mock URLSession delegate, use in-memory SwiftData container.

**Test cases:**
- Download creates correct directory structure
- Duplicate download prevented
- Cancel removes partial file
- Delete removes file + cleans empty directories
- File size tracked correctly

## Mock Server Plan

For integration testing beyond unit tests:

### Option A: In-Process Mock Server
- Use Swift's `URLProtocol` subclass to intercept requests
- Return fixture JSON from bundled test resources
- No actual network needed, fast, deterministic

### Option B: Local HTTP Server
- Lightweight HTTP server in test setup (e.g., Embassy, Swifter)
- Better for testing timeout/retry behavior
- More realistic but slower

**Recommendation:** Start with Option A (URLProtocol) for unit tests, add Option B later for integration tests.

## Test Infrastructure Roadmap

| Sprint | Tests | Coverage |
|--------|-------|----------|
| Sprint 3 | 96 | Models, Auth, Utilities, ErrorPresenter |
| Sprint 4-8 | +399 | Audio, queue, cache, EQ, replay gain, endpoints, widgets, ratings, biography, ListenBrainz |
| Sprint 9+ | +185 | XCUITest for iOS (95) and macOS (90): playback, navigation, settings, rotation, playlists, radio |
| **Current** | **680** | **Full cross-platform: 924 total (iOS 680 + Android 124 + Web 120)** |

## Coverage Goals

| Target | Current | Goal (v1.0) | Goal (v2.0) |
|--------|---------|-------------|-------------|
| Models/Networking | ~90% | 95% | 95% |
| Core Audio | 0% | 30% (queue logic) | 60% |
| Core Downloads | 0% | 20% | 50% |
| Features/Views | 0% | 0% | 20% (UI tests) |
| Overall | ~10% | 25% | 40% |
