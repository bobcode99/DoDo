import SwiftUI

/// Reusable playback transport row.
///
/// - `.expanded` is the full layout: speed Menu, large skip / play / skip,
///   and a sleep-timer Menu. Used by iOS `ExpandedPlayerView` and the macOS
///   `MacExpandedPlayerView`.
/// - `.compact` strips down to just skip / play / skip at mini-bar sizing.
///   Used by the macOS `MacMiniPlayerBar`. Hosting view supplies its own
///   speed / sleep affordances when needed.
struct PlayerControlsView: View {
    enum Style {
        case expanded
        case compact
    }

    let viewModel: ExpandedPlayerViewModel
    var style: Style = .expanded

    @AppStorage("skipForwardInterval") private var skipForwardInterval: Int = 30
    @AppStorage("skipBackwardInterval") private var skipBackwardInterval: Int = 15

    private static let speedOptions: [Float] = Formatters.playbackSpeeds

    var body: some View {
        switch style {
        case .expanded: expandedBody
        case .compact:  compactBody
        }
    }

    // MARK: - Expanded

    private var expandedBody: some View {
        HStack(spacing: 0) {
            speedMenu

            Spacer()

            transportRow(
                playSize: 72, skipSize: 32,
                spacing: 28, playFrame: 80, skipFrame: 60
            )

            Spacer()

            sleepTimerMenu
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Compact

    private var compactBody: some View {
        transportRow(
            playSize: 28, skipSize: 18,
            spacing: 20, playFrame: 36, skipFrame: 28
        )
    }

    // MARK: - Pieces

    private var speedMenu: some View {
        Menu {
            ForEach(Self.speedOptions, id: \.self) { speed in
                Button {
                    viewModel.setPlaybackSpeed(speed)
                } label: {
                    HStack {
                        Text(Formatters.formatSpeed(speed))
                        if abs(viewModel.playbackSpeed - speed) < 0.01 {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(Formatters.formatSpeed(viewModel.playbackSpeed))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .glassEffect(.regular, in: .circle)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 56, height: 56)
        .contentShape(Rectangle())
        .accessibilityLabel("Playback speed \(Formatters.formatSpeed(viewModel.playbackSpeed))")
    }

    @ViewBuilder
    private func transportRow(
        playSize: CGFloat,
        skipSize: CGFloat,
        spacing: CGFloat,
        playFrame: CGFloat,
        skipFrame: CGFloat
    ) -> some View {
        HStack(spacing: spacing) {
            Button(action: viewModel.skipBackward) {
                Image(systemName: "gobackward.\(skipBackwardInterval)")
                    .font(.system(size: skipSize))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .frame(width: skipFrame)
            .accessibilityLabel("Skip back \(skipBackwardInterval) seconds")

            Button(action: viewModel.togglePlayPause) {
                Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: playSize))
                    .foregroundStyle(.primary)
                    // SF Symbols' default `.replace` content transition runs a
                    // ~0.25s crossfade between play and pause glyphs, which
                    // makes the central button feel laggy on tap. `.identity`
                    // swaps the glyph on the next frame instead.
                    .contentTransition(.identity)
            }
            .buttonStyle(.plain)
            .frame(width: playFrame)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
            // Strip any animation inherited from the ExpandedPlayerView
            // transition so the button doesn't crossfade its layout on tap.
            .transaction { $0.animation = nil }

            Button(action: viewModel.skipForward) {
                Image(systemName: "goforward.\(skipForwardInterval)")
                    .font(.system(size: skipSize))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .frame(width: skipFrame)
            .accessibilityLabel("Skip forward \(skipForwardInterval) seconds")
        }
    }

    private var sleepTimerMenu: some View {
        Menu {
            ForEach(SleepTimerOption.allCases, id: \.self) { option in
                Button(action: { viewModel.setSleepTimer(option) }) {
                    Label(option.displayName, systemImage: option.systemImage)
                    if viewModel.sleepTimerOption == option {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Group {
                if viewModel.isSleepTimerActive {
                    if viewModel.sleepTimerOption == .endOfEpisode {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                    } else {
                        Text(viewModel.sleepTimerRemainingFormatted)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                    }
                } else {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 22))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 48, height: 48)
            .glassEffect(viewModel.isSleepTimerActive ? .regular.tint(.white.opacity(0.35)) : .regular, in: .circle)
            .frame(width: 56, height: 56)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel(viewModel.isSleepTimerActive ? "Sleep timer active" : "Sleep timer")
    }
}
