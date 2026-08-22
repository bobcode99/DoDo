//
//  DiscoveryRegionsView.swift
//  PodcastAnalyzer
//
//  Choose which Apple Podcasts storefronts Home offers.
//
//  There are 174 live storefronts and most people follow one or two, so the
//  ticked ones are pinned to the top in the order Home shows them, and the
//  rest sit under a search field. A storefront Apple hasn't published — or one
//  too new to be in the shipped list — can be added by code once a probe
//  confirms it answers.
//

import SwiftUI

struct DiscoveryRegionsView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var regions = DiscoveryRegions.shared

  @State private var search = ""
  @State private var customCode = ""
  @State private var probeState: ProbeState = .idle

  private enum ProbeState: Equatable {
    case idle
    case probing
    case available(String)
    case unavailable(String)
  }

  /// Catalogue minus what's already ticked, filtered by the search field.
  /// Matching on code as well as name so "tw" finds Taiwan.
  private var searchResults: [Storefront] {
    let enabled = Set(regions.enabled)
    let pool = Storefront.all.filter { !enabled.contains($0.code) }
    let query = search.trimmingCharacters(in: .whitespaces).lowercased()
    guard !query.isEmpty else { return pool }
    return pool.filter {
      $0.name.lowercased().contains(query) || $0.code.contains(query)
    }
  }

  var body: some View {
    NavigationStack {
      List {
        chosenSection
        customSection
        catalogueSection
      }
      .searchable(text: $search, prompt: "Search countries")
      .navigationTitle("Discovery Regions")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      .environment(\.editMode, .constant(.active))
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  // MARK: - Chosen

  private var chosenSection: some View {
    Section {
      ForEach(regions.enabledStorefronts) { region in
        HStack {
          Text(region.flag).font(.title2)
          Text(region.name)
          Spacer()
          if !Storefront.isKnown(region.code) {
            Text("Custom")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          // The last remaining region can't be removed: an empty shortlist
          // leaves Home with nothing to show and no way to recover.
          Button {
            regions.toggle(region.code)
          } label: {
            Image(systemName: "minus.circle.fill")
              .foregroundStyle(regions.enabled.count > 1 ? .red : .secondary)
          }
          .buttonStyle(.plain)
          .disabled(regions.enabled.count <= 1)
        }
      }
      .onMove { source, destination in
        var codes = regions.enabled
        codes.move(fromOffsets: source, toOffset: destination)
        regions.setEnabled(codes)
      }
    } header: {
      Text("Shown on Home")
    } footer: {
      Text("Drag to reorder. Home's region switcher offers these, in this order.")
    }
  }

  // MARK: - Custom storefront

  private var customSection: some View {
    Section {
      HStack {
        TextField("Country code (e.g. pt)", text: $customCode)
          .autocorrectionDisabled()
          #if os(iOS)
          .textInputAutocapitalization(.never)
          #endif
          .onChange(of: customCode) { _, _ in probeState = .idle }

        Button("Test") {
          Task { await probe() }
        }
        .buttonStyle(.bordered)
        .disabled(customCode.trimmingCharacters(in: .whitespaces).isEmpty
                  || probeState == .probing)
      }

      switch probeState {
      case .idle:
        EmptyView()
      case .probing:
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text("Checking…").foregroundStyle(.secondary)
        }
      case .available(let code):
        Label("\(code.uppercased()) is available — added.", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
      case .unavailable(let code):
        Label("\(code.uppercased()) isn't an Apple Podcasts storefront.", systemImage: "xmark.circle.fill")
          .foregroundStyle(.red)
      }
    } header: {
      Text("Add by code")
    } footer: {
      Text("For a storefront that isn't listed. Test checks it against Apple before adding it.")
    }
  }

  private func probe() async {
    let code = customCode.trimmingCharacters(in: .whitespaces).lowercased()
    guard !code.isEmpty else { return }
    probeState = .probing

    if await ApplePodcastService().probeStorefront(code) {
      regions.addCustom(code)
      probeState = .available(code)
      customCode = ""
    } else {
      probeState = .unavailable(code)
    }
  }

  // MARK: - Catalogue

  private var catalogueSection: some View {
    Section {
      ForEach(searchResults) { region in
        Button {
          regions.toggle(region.code)
        } label: {
          HStack {
            Text(region.flag).font(.title2)
            Text(region.name).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "plus.circle")
              .foregroundStyle(.tint)
          }
        }
      }
    } header: {
      Text("All regions")
    } footer: {
      Text("\(Storefront.all.count) Apple Podcasts storefronts.")
    }
  }
}
