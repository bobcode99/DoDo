//
//  SpeedPickerOverlay.swift
//  PodcastAnalyzer
//
//  Speed picker overlay and speed button for the expanded player.
//

import SwiftUI

// MARK: - Speed Picker Overlay (Apple Podcasts Style with Slider)

struct SpeedPickerOverlay: View {
  let currentSpeed: Float
  let quickSpeeds: [Float]
  let allSpeeds: [Float]
  let onSelectSpeed: (Float) -> Void
  let onDismiss: () -> Void

  @State private var showAllSpeeds = false
  @State private var sliderValue: Float
  @State private var lastHapticSpeed: Float = 0
  @State private var hapticTrigger = false

  private let speedStops: [Float] = Formatters.playbackSpeeds

  init(currentSpeed: Float, quickSpeeds: [Float], allSpeeds: [Float], onSelectSpeed: @escaping (Float) -> Void, onDismiss: @escaping () -> Void) {
    self.currentSpeed = currentSpeed
    self.quickSpeeds = quickSpeeds
    self.allSpeeds = allSpeeds
    self.onSelectSpeed = onSelectSpeed
    self.onDismiss = onDismiss
    self._sliderValue = State(initialValue: currentSpeed)
    self._lastHapticSpeed = State(initialValue: currentSpeed)
  }

  var body: some View {
    ZStack {
      Color.black.opacity(0.4)
        .ignoresSafeArea()
        .onTapGesture { onDismiss() }

      VStack(spacing: 0) {
        // Header
        HStack {
          Image(systemName: "waveform")
            .foregroundStyle(.secondary)
          Text("Playback Speed")
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.primary)
          Spacer()

          Text(Formatters.formatSpeed(sliderValue))
            .font(.title2)
            .fontWeight(.bold)
            .foregroundStyle(.blue)
            .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)

        Divider()
          .padding(.horizontal, 12)

        // Speed slider
        VStack(spacing: 8) {
          Slider(
            value: $sliderValue,
            in: 0.5...2.0,
            step: 0.05
          ) {
            Text("Speed")
          } minimumValueLabel: {
            Text("0.5x")
              .font(.caption2)
              .foregroundStyle(.secondary)
          } maximumValueLabel: {
            Text("2x")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          .tint(.blue)
          .onChange(of: sliderValue) { oldValue, newValue in
            for stop in speedStops {
              let crossedForward = oldValue < stop && newValue >= stop
              let crossedBackward = oldValue > stop && newValue <= stop
              if crossedForward || crossedBackward {
                hapticTrigger.toggle()
                break
              }
            }
          }
          .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)

          // Speed stop markers
          HStack {
            ForEach(speedStops, id: \.self) { stop in
              if stop == speedStops.first {
                Circle()
                  .fill(sliderValue >= stop ? Color.blue : Color.gray.opacity(0.3))
                  .frame(width: 6, height: 6)
              } else if stop == speedStops.last {
                Spacer()
                Circle()
                  .fill(sliderValue >= stop ? Color.blue : Color.gray.opacity(0.3))
                  .frame(width: 6, height: 6)
              } else {
                Spacer()
                Circle()
                  .fill(sliderValue >= stop ? Color.blue : Color.gray.opacity(0.3))
                  .frame(width: 6, height: 6)
              }
            }
          }
          .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)

        Divider()
          .padding(.horizontal, 12)

        // Quick speed buttons
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(showAllSpeeds ? allSpeeds : quickSpeeds, id: \.self) { speed in
              SpeedButton(
                speed: speed,
                isSelected: abs(sliderValue - speed) < 0.03,
                onTap: {
                  withAnimation(.easeInOut(duration: 0.2)) {
                    sliderValue = speed
                  }
                  hapticTrigger.toggle()
                  onSelectSpeed(speed)
                }
              )
            }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)

        // "More Speeds" hint and Apply button
        HStack {
          Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
              showAllSpeeds.toggle()
            }
          }) {
            HStack(spacing: 4) {
              Text(showAllSpeeds ? "Show Less" : "More Speeds")
                .font(.caption)
                .foregroundStyle(.secondary)
              Image(systemName: showAllSpeeds ? "chevron.up" : "chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }

          Spacer()

          Button("Apply") {
            onSelectSpeed(sliderValue)
          }
          .buttonStyle(.glassProminent)
          .font(.subheadline)
          .fontWeight(.semibold)
          .padding(.horizontal, 20)
          .padding(.vertical, 8)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
      }
      .glassEffect(Glass.regular, in: .rect(cornerRadius: 16))
      .padding(.horizontal, 24)
    }
  }

}

// MARK: - Speed Button

struct SpeedButton: View {
  let speed: Float
  let isSelected: Bool
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      speedLabel
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var speedLabel: some View {
    let label = Text(Formatters.formatSpeed(speed))
      .font(.subheadline)
      .fontWeight(isSelected ? .bold : .medium)
      .foregroundStyle(isSelected ? .white : .primary)
      .frame(minWidth: 44, minHeight: 36)
      .padding(.horizontal, 12)

    if isSelected {
      label
        .background(Capsule().fill(Color.blue))
    } else {
      label
        .glassEffect(Glass.regular.interactive(), in: .capsule)
    }
  }
}
