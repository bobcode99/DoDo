//
//  RegionToggleRow.swift
//  PodcastAnalyzer
//
//  One selectable storefront on the onboarding region page.
//

#if os(iOS)
import SwiftUI

struct RegionToggleRow: View {
  let region: Storefront
  let isOn: Bool
  let isLocked: Bool
  let onToggle: () -> Void

  var body: some View {
    Button(action: onToggle) {
      HStack {
        Text(region.flag)
          .font(.title2)
          .accessibilityHidden(true)
        Text(region.name)
          .foregroundStyle(.primary)
        Spacer()
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(.thinMaterial, in: .rect(cornerRadius: 12))
    }
    .buttonStyle(.plain)
    .disabled(isLocked)
    // The checkmark is the only visual difference between states, so state has
    // to reach VoiceOver some other way than color.
    .accessibilityAddTraits(isOn ? .isSelected : [])
  }
}

#Preview {
  RegionToggleRow(
    region: Storefront(code: "tw", name: "Taiwan"),
    isOn: true,
    isLocked: false,
    onToggle: {}
  )
  .padding()
}

#endif
