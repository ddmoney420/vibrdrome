import SwiftUI

@main
struct ProjectMSpikeApp: App {
    var body: some Scene {
        WindowGroup {
            GLClearContainer()
                .ignoresSafeArea()
        }
    }
}

#if canImport(UIKit)
import UIKit
struct GLClearContainer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> GLClearViewController { GLClearViewController() }
    func updateUIViewController(_ vc: GLClearViewController, context: Context) {}
}
#else
import AppKit
struct GLClearContainer: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> GLClearViewController { GLClearViewController() }
    func updateNSViewController(_ vc: GLClearViewController, context: Context) {}
}
#endif
