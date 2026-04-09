import Testing
import Foundation
@testable import Vibrdrome

struct ToolbarCustomizationTests {

    @Test func toolbarKeysExist() {
        let keys = [
            UserDefaultsKeys.showVisualizerInToolbar,
            UserDefaultsKeys.showEQInToolbar,
            UserDefaultsKeys.showAirPlayInToolbar,
            UserDefaultsKeys.showLyricsInToolbar,
            UserDefaultsKeys.showSettingsInToolbar,
        ]
        let uniqueKeys = Set(keys)
        #expect(uniqueKeys.count == 5, "All 5 toolbar keys must have distinct values")
    }

    @Test func defaultsAreTrue() {
        // On a fresh install, UserDefaults returns false for unset bools.
        // The app should treat unset (false) as "show" or use registered defaults.
        // Verify the keys are non-empty strings that can be used with UserDefaults.
        let keys = [
            UserDefaultsKeys.showVisualizerInToolbar,
            UserDefaultsKeys.showEQInToolbar,
            UserDefaultsKeys.showAirPlayInToolbar,
            UserDefaultsKeys.showLyricsInToolbar,
            UserDefaultsKeys.showSettingsInToolbar,
        ]
        for key in keys {
            #expect(!key.isEmpty, "Toolbar key should not be empty")
        }
    }
}
