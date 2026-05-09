#if os(iOS)
import MediaPlayer
import SwiftUI
import UIKit

/// Wraps MPVolumeView for system volume control in SwiftUI.
/// Route button is hidden — AirPlayButton (AVRoutePickerView) is used separately.
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        MPVolumeView(frame: .zero)
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        for subview in uiView.subviews where subview is UIButton {
            subview.isHidden = true
        }
    }
}
#endif
