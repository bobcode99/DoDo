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

    @Environment(\.locale) private var locale
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

    // Sized so the whole row fits inside the player's 32pt gutters on the
    // narrowest iPhone (393pt): 52 + 22 + 74 + 22 + 52 transport, plus two 44pt
    // menus, leaves real space for the flanking Spacers instead of collapsing
    // them and letting the glass circles crowd the transport.
    private var expandedBody: some View {
        HStack(spacing: 0) {
            speedMenu

            Spacer(minLength: 8)

            transportRow(
                playSize: 68, skipSize: 30,
                spacing: 22, playFrame: 74, skipFrame: 52
            )

            Spacer(minLength: 8)

            sleepTimerMenu
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Compact

    private var compactBody: some View {
        transportRow(
            playSize: 28, skipSize: 18,
            spacing: 20, playFrame: 36, skipFrame: 28
        )
    }

    // MARK: - Pieces

    /// The glyph alone is about 30pt tall; the iOS layout gives each skip button a 44pt target.
    /// The compact style belongs to the macOS mini bar, which keeps its glyph-sized rows.
    private var skipHeight: CGFloat? { style == .expanded ? 44 : nil }

    private var speedMenu: some View {
        @Bindable var viewModel = viewModel
        return Menu {
            Picker("Playback speed", selection: $viewModel.selectedSpeed) {
                ForEach(Self.speedOptions, id: \.self) { speed in
                    Text(Formatters.formatSpeed(speed)).tag(Float?.some(speed))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text(Formatters.formatSpeed(viewModel.playbackSpeed))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: .circle)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 44, height: 44)
        .contentShape(.rect)
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
                    .frame(width: skipFrame, height: skipHeight)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
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
            #if os(iOS)
            // macOS gets Space from the Controls menu (MacPlaybackCommands).
            .keyboardShortcut(.space, modifiers: [])
            #endif
            .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
            // Strip any animation inherited from the ExpandedPlayerView
            // transition so the button doesn't crossfade its layout on tap.
            .transaction { $0.animation = nil }

            Button(action: viewModel.skipForward) {
                Image(systemName: "goforward.\(skipForwardInterval)")
                    .font(.system(size: skipSize))
                    .foregroundStyle(.primary)
                    .frame(width: skipFrame, height: skipHeight)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip forward \(skipForwardInterval) seconds")
        }
    }

    private var sleepTimerMenu: some View {
        Menu {
            // Buttons, not a Picker: a Picker skips its setter when the current
            // option is picked again, and re-picking is how a running timer restarts.
            ForEach(SleepTimerOption.allCases, id: \.self) { option in
                let isSelected = viewModel.sleepTimerOption == option
                Button {
                    viewModel.sleepTimerOption = option
                } label: {
                    Label(option.displayName, systemImage: isSelected ? "checkmark" : option.systemImage)
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        } label: {
            Group {
                if viewModel.isSleepTimerActive {
                    if viewModel.sleepTimerOption == .endOfEpisode {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.primary)
                    } else {
                        Text(viewModel.sleepTimerRemainingFormatted)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.5)
                    }
                } else {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 22))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 44, height: 44)
            .glassEffect(viewModel.isSleepTimerActive ? .regular.tint(.white.opacity(0.35)) : .regular, in: .circle)
            .frame(width: 44, height: 44)
            .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel(viewModel.isSleepTimerActive ? "Sleep timer active" : "Sleep timer")
        .accessibilityValue(sleepTimerRemainingSpoken)
    }

    /// The countdown as words ("4 minutes, 12 seconds"); the label's "4:12" would be read as a clock time.
    private var sleepTimerRemainingSpoken: String {
        guard viewModel.sleepTimerRemaining > 0 else { return "" }
        return Duration.seconds(viewModel.sleepTimerRemaining)
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide, maximumUnitCount: 2).locale(locale))
    }
}
