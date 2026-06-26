//
//  RegionPickerSheet.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/3/14.
//


import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct RegionPickerSheet: View {
  @Binding var selectedRegion: String
  @Binding var isPresented: Bool

  var body: some View {
    NavigationStack {
      List {
        ForEach(Constants.podcastRegions, id: \.code) { region in
          Button(action: {
            selectedRegion = region.code
            isPresented = false
          }) {
            HStack {
              Text(region.flag)
                .font(.title2)
              Text(region.name)
                .foregroundStyle(.primary)

              Spacer()

              if selectedRegion == region.code {
                Image(systemName: "checkmark")
                  .foregroundStyle(.blue)
              }
            }
          }
        }
      }
      .navigationTitle("Select Region")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            isPresented = false
          }
        }
      }
    }
  }
}