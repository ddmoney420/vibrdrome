#if os(iOS)
import AVKit
import SwiftUI

struct AirPlayButton: UIViewRepresentable {
    var tintColor: UIColor = .secondaryLabel

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = tintColor
        picker.activeTintColor = .systemBlue
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tintColor
    }
}
#endif
