import Testing
import Foundation
@testable import Vibrdrome

/// Tests for ListenBrainz client configuration and payload construction.
/// Note: isEnabled tests that depend on Keychain token are skipped because
/// the test target doesn't link KeychainAccess directly. The toggle-off
/// and key-value tests still verify the UserDefaults side.
struct ListenBrainzTests {

    // MARK: - isEnabled Logic

    @Test func isDisabledWhenToggleOff() async {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: UserDefaultsKeys.listenBrainzEnabled)
        let enabled = await ListenBrainzClient.shared.isEnabled
        #expect(!enabled)
        defaults.removeObject(forKey: UserDefaultsKeys.listenBrainzEnabled)
    }

    // MARK: - Key Values

    @Test func listenBrainzKeyValues() {
        #expect(UserDefaultsKeys.listenBrainzEnabled == "listenBrainzEnabled")
        #expect(UserDefaultsKeys.listenBrainzToken == "listenBrainzToken")
    }

    @Test func listenBrainzKeysAreDistinct() {
        #expect(UserDefaultsKeys.listenBrainzEnabled != UserDefaultsKeys.listenBrainzToken)
        #expect(UserDefaultsKeys.listenBrainzEnabled != UserDefaultsKeys.scrobblingEnabled)
    }
}
