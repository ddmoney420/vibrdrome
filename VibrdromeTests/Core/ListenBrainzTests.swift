import Testing
import Foundation
@testable import Vibrdrome

/// Tests for ListenBrainz client configuration and payload construction.
struct ListenBrainzTests {

    // MARK: - isEnabled Logic

    @Test func isDisabledWhenToggleOff() async {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: UserDefaultsKeys.listenBrainzEnabled)
        defaults.set("test-token", forKey: UserDefaultsKeys.listenBrainzToken)
        let enabled = await ListenBrainzClient.shared.isEnabled
        #expect(!enabled)
        defaults.removeObject(forKey: UserDefaultsKeys.listenBrainzEnabled)
        defaults.removeObject(forKey: UserDefaultsKeys.listenBrainzToken)
    }

    @Test func isDisabledWhenNoToken() async {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: UserDefaultsKeys.listenBrainzEnabled)
        defaults.removeObject(forKey: UserDefaultsKeys.listenBrainzToken)
        let enabled = await ListenBrainzClient.shared.isEnabled
        #expect(!enabled)
        defaults.removeObject(forKey: UserDefaultsKeys.listenBrainzEnabled)
    }

    @Test func isDisabledWhenEmptyToken() async {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: UserDefaultsKeys.listenBrainzEnabled)
        defaults.set("", forKey: UserDefaultsKeys.listenBrainzToken)
        let enabled = await ListenBrainzClient.shared.isEnabled
        #expect(!enabled)
        defaults.removeObject(forKey: UserDefaultsKeys.listenBrainzEnabled)
        defaults.removeObject(forKey: UserDefaultsKeys.listenBrainzToken)
    }

    @Test func isEnabledWhenToggleOnAndTokenSet() async {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: UserDefaultsKeys.listenBrainzEnabled)
        defaults.set("valid-token-123", forKey: UserDefaultsKeys.listenBrainzToken)
        let enabled = await ListenBrainzClient.shared.isEnabled
        #expect(enabled)
        defaults.removeObject(forKey: UserDefaultsKeys.listenBrainzEnabled)
        defaults.removeObject(forKey: UserDefaultsKeys.listenBrainzToken)
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
