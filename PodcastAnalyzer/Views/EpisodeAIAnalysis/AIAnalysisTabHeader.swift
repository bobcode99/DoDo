//
//  AIAnalysisTabHeader.swift
//  PodcastAnalyzer
//
//  Title + description header shared by the Analysis and Ask Question tabs.
//

import SwiftUI

struct AIAnalysisTabHeader: View {
  let title: LocalizedStringResource
  let description: LocalizedStringResource

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.title2)
        .bold()
      Text(description)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}
