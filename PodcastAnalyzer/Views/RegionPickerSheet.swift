//
//  RegionPickerSheet.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/3/14.
//
//  Home's storefront switcher. Offers only the regions the user ticked, not
//  the full 174-entry catalogue — switching between the two countries someone
//  actually follows should not mean scrolling past Andorra. Managing the
//  shortlist lives one tap away, in Settings' own screen.
//

import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct RegionPickerSheet: View {
  @Binding var selectedRegion: String
  @Binding var isPresented: Bool

  @State private var regions = DiscoveryRegions.shared
  @State private var showingManage = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(regions.enabledStorefronts) { region in
            Button {
              selectedRegion = region.code
              isPresented = false
            } label: {
              HStack {
                Text(region.flag)
                  .font(.title2)
                Text(region.name)
                  .foregroundStyle(.primary)

                Spacer()

                if selectedRegion == region.code {
                  Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                }
              }
            }
          }
        } footer: {
          Text("Only the regions you've chosen appear here.")
        }

        Section {
          Button {
            showingManage = true
          } label: {
            Label("Manage Regions", systemImage: "globe")
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
      .sheet(isPresented: $showingManage) {
        DiscoveryRegionsView()
      }
    }
  }
}
