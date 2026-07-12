//
//  TypingDotsView.swift
//  PodcastAnalyzer
//
//  Three dots that fade in/out in sequence, used to indicate an answer is in flight.
//

import SwiftUI

struct TypingDotsView: View {
  @State private var animate = false

  var body: some View {
    HStack(spacing: 6) {
      ForEach(0..<3, id: \.self) { index in
        Circle()
          .fill(Color.secondary)
          .frame(width: 6, height: 6)
          .opacity(animate ? 1 : 0.3)
          .animation(
            .easeInOut(duration: 0.6)
              .repeatForever(autoreverses: true)
              .delay(Double(index) * 0.15),
            value: animate
          )
      }
    }
    .onAppear { animate = true }
  }
}
