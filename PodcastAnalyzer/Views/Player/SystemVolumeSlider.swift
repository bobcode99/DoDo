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
        // Monochrome to match the scrubber instead of the system-accent blue.
        uiView.tintColor = .label
        uiView.setMaximumVolumeSliderImage(SystemVolumeSlider.trackImage, for: .normal)
        uiView.setMinimumVolumeSliderImage(SystemVolumeSlider.trackImage, for: .normal)
        uiView.setVolumeThumbImage(SystemVolumeSlider.thumbImage, for: .normal)
        for subview in uiView.subviews where subview is UIButton {
            subview.isHidden = true
        }
    }

    // 2pt-tall rounded track, capsule white thumb — same monochrome language
    // as ThumblessSlider's `.label` track in SmoothScrubber.
    private static let trackImage: UIImage = {
        let height: CGFloat = 3
        let size = CGSize(width: height, height: height)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.label.withAlphaComponent(0.18).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: height / 2).fill()
        }.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: height / 2, bottom: 0, right: height / 2))
    }()

    private static let thumbImage: UIImage = {
        let diameter: CGFloat = 14
        let size = CGSize(width: diameter, height: diameter)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.label.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
        }
    }()
}
#endif
