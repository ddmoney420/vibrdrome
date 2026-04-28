import SwiftUI

private struct ContentWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var contentWidth: CGFloat {
        get { self[ContentWidthKey.self] }
        set { self[ContentWidthKey.self] = newValue }
    }
}
