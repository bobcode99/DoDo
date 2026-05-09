import SwiftUI

struct PlayerControlsView: View {
    var viewModel: ExpandedPlayerViewModel
    let onOpenSpeedPicker: () -> Void

    @AppStorage("skipForwardInterval") private var skipForwardInterval: Int = 30
    @AppStorage("skipBackwardInterval") private var skipBackwardInterval: Int = 15

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpenSpeedPicker) {
                Text(Formatters.formatSpeed(viewModel.playbackSpeed))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .glassEffect(.regular, in: .circle)
            }
            .frame(width: 56, height: 56)
            .contentShape(Rectangle())
            .accessibilityLabel("Playback speed \(Formatters.formatSpeed(viewModel.playbackSpeed))")

            Spacer()

            HStack(spacing: 28) {
                Button(action: viewModel.skipBackward) {
                    Image(systemName: "gobackward.\(skipBackwardInterval)")
                        .font(.system(size: 32))
                        .foregroundStyle(.primary)
                }
                .frame(width: 60)
                .accessibilityLabel("Skip back \(skipBackwardInterval) seconds")

                Button(action: viewModel.togglePlayPause) {
                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.primary)
                }
                .frame(width: 80)
                .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")

                Button(action: viewModel.skipForward) {
                    Image(systemName: "goforward.\(skipForwardInterval)")
                        .font(.system(size: 32))
                        .foregroundStyle(.primary)
                }
                .frame(width: 60)
                .accessibilityLabel("Skip forward \(skipForwardInterval) seconds")
            }

            Spacer()

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
                .glassEffect(viewModel.isSleepTimerActive ? .regular.tint(.blue) : .regular, in: .circle)
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(viewModel.isSleepTimerActive ? "Sleep timer active" : "Sleep timer")
        }
        .padding(.horizontal, 24)
    }
}
