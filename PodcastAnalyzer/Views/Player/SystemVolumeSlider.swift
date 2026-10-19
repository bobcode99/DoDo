#if os(iOS)
import MediaPlayer
import SwiftUI

/// Wraps MPVolumeView for system volume control in SwiftUI, styled to match
/// ThumblessSlider in SmoothScrubber: 4pt capsule track with a solid filled
/// part, white shadowed thumb that grows while held.
/// Route button is hidden — AirPlayButton (AVRoutePickerView) is used separately.
struct SystemVolumeSlider: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> CenteredVolumeView {
        let view = CenteredVolumeView(frame: .zero)
        view.setVolumeThumbImage(Self.thumbImage(diameter: 12), for: .normal)
        view.setVolumeThumbImage(Self.thumbImage(diameter: 16), for: .highlighted)
        return view
    }

    func updateUIView(_ uiView: CenteredVolumeView, context: Context) {
        // Track images are baked bitmaps, so resolve `.label` for the current
        // scheme here instead of once in a static (which would stick to
        // whichever mode the app launched in).
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let fill = UIColor.label.resolvedColor(with: traits)
        uiView.setMinimumVolumeSliderImage(Self.trackImage(fill), for: .normal)
        uiView.setMaximumVolumeSliderImage(Self.trackImage(fill.withAlphaComponent(0.18)), for: .normal)
        for subview in uiView.subviews where subview is UIButton {
            subview.isHidden = true
        }
    }

    private static func trackImage(_ color: UIColor) -> UIImage {
        let height: CGFloat = 4
        let size = CGSize(width: height, height: height)
        return UIGraphicsImageRenderer(size: size).image { _ in
            color.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: height / 2).fill()
        }.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: height / 2, bottom: 0, right: height / 2))
    }

    private static func thumbImage(diameter: CGFloat) -> UIImage {
        // Room around the circle for the shadow, same 3pt blur / 1pt drop as the scrubber.
        let inset: CGFloat = 4
        let size = CGSize(width: diameter + inset * 2, height: diameter + inset * 2)
        return UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.setShadow(
                offset: CGSize(width: 0, height: 1),
                blur: 3,
                color: UIColor.black.withAlphaComponent(0.3).cgColor
            )
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: inset, y: inset, width: diameter, height: diameter)).fill()
        }
    }
}

/// MPVolumeView pins its slider to the top of its bounds; center it so it
/// lines up with the speaker glyphs beside it.
final class CenteredVolumeView: MPVolumeView {
    override func volumeSliderRect(forBounds bounds: CGRect) -> CGRect {
        let rect = super.volumeSliderRect(forBounds: bounds)
        return rect.offsetBy(dx: 0, dy: bounds.midY - rect.midY)
    }
}
#endif
