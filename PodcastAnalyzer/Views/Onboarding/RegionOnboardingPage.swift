//
//  RegionOnboardingPage.swift
//  PodcastAnalyzer
//
//  Which countries' charts Home should offer.
//
//  The device region is already ticked when this appears, so the page is
//  skippable — it exists to let someone who follows, say, Taiwanese and US
//  shows set both up front rather than discovering the switcher later.
//

#if os(iOS)
import SwiftUI

struct RegionOnboardingPage: View {
  let onNext: () -> Void

  @State private var regions = DiscoveryRegions.shared

  /// A short, broad list. The full 174 live in Settings; offering them here
  /// would turn a setup step into a scroll.
  private var suggestions: [Storefront] {
    let codes = [Constants.defaultRegion, "us", "gb", "tw", "jp", "kr", "de", "fr", "ca", "au"]
    var seen = Set<String>()
    return codes
      .filter { seen.insert($0).inserted }
      .compactMap { Storefront.named($0) }
  }

  var body: some View {
    VStack(spacing: 0) {
      Spacer()

      Image(systemName: "globe")
        .font(.system(size: 64))
        .foregroundStyle(.tint)
        .padding(.bottom, 24)

      Text("Where do you listen?")
        .font(.title)
        .bold()
        .multilineTextAlignment(.center)

      Text("Pick the countries whose charts you want on Home. You can change this any time in Settings.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .padding(.top, 8)

      ScrollView {
        VStack(spacing: 8) {
          ForEach(suggestions) { region in
            RegionToggleRow(
              region: region,
              isOn: regions.enabled.contains(region.code),
              // The last one can't be unticked — Home needs somewhere to look.
              isLocked: regions.enabled.contains(region.code) && regions.enabled.count <= 1,
              onToggle: { regions.toggle(region.code) }
            )
          }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
      }
      .frame(maxHeight: 320)

      Spacer()

      Button(action: onNext) {
        Text("Continue")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
      }
      .buttonStyle(.accentProminent)
      .padding(.horizontal, 32)
      .padding(.bottom, 60)
    }
  }
}

#Preview {
  RegionOnboardingPage(onNext: {})
}

#endif
