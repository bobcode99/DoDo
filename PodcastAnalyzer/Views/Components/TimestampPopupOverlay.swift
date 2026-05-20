//
//  TimestampPopupOverlay.swift
//  PodcastAnalyzer
//
//  Reusable overlay that renders the floating TimestampPopup at the location
//  of the user's most recent tap. Used by the Summary landing page on iOS
//  and macOS so a tapped inline timestamp can offer Play / Share actions.
//

import SwiftUI

extension View {
    /// Overlays a TimestampPopup anchored to (`tapX`, `tapY`) when
    /// `tappedSeconds` is non-nil. Tapping anywhere outside dismisses.
    func timestampPopup(
        viewModel: EpisodeDetailViewModel,
        tappedSeconds: Binding<TimeInterval?>,
        tapX: CGFloat,
        tapY: CGFloat
    ) -> some View {
        overlay {
            TimestampPopupOverlay(
                viewModel: viewModel,
                tappedSeconds: tappedSeconds,
                tapX: tapX,
                tapY: tapY
            )
        }
    }
}

private struct TimestampPopupOverlay: View {
    let viewModel: EpisodeDetailViewModel
    @Binding var tappedSeconds: TimeInterval?
    let tapX: CGFloat
    let tapY: CGFloat

    var body: some View {
        if let seconds = tappedSeconds {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { tappedSeconds = nil }
                .overlay {
                    GeometryReader { geo in
                        let popupWidth: CGFloat = 240
                        let popupHeight: CGFloat = 110
                        let x = min(
                            max(tapX, popupWidth / 2 + 16),
                            geo.size.width - popupWidth / 2 - 16
                        )
                        let showAbove = tapY > geo.size.height - popupHeight - 60
                        let y = showAbove
                            ? tapY - popupHeight / 2 - 10
                            : tapY + popupHeight / 2 + 10

                        TimestampPopup(
                            seconds: seconds,
                            onPlay: {
                                viewModel.seekToTime(seconds)
                                tappedSeconds = nil
                            },
                            onShare: {
                                viewModel.shareTimestampedLink(seconds: seconds)
                                tappedSeconds = nil
                            }
                        )
                        .position(x: x, y: y)
                        .transition(
                            .scale(scale: 0.88, anchor: showAbove ? .bottom : .top)
                            .combined(with: .opacity)
                        )
                    }
                }
                .animation(.spring(response: 0.22, dampingFraction: 0.75), value: tappedSeconds != nil)
        }
    }
}
