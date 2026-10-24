//
//  StorageUsageRow.swift
//  PodcastAnalyzer
//
//  One clearable category on the Storage screen: icon, title, current size, and
//  a destructive action behind its own confirmation. The dialog lives on the row
//  so iPad anchors its popover to the button that was tapped.
//

import SwiftUI

struct StorageUsageRow: View {
  let systemImage: String
  let tint: Color
  let title: LocalizedStringKey
  /// nil while the size is still being calculated.
  let detail: Text?
  let actionTitle: LocalizedStringKey
  let actionTint: Color
  let isBusy: Bool
  let isDisabled: Bool
  let confirmationTitle: LocalizedStringKey
  let confirmationMessage: LocalizedStringKey
  let confirmButtonTitle: LocalizedStringKey
  let onConfirm: () -> Void

  @State private var isConfirming = false

  var body: some View {
    Button {
      isConfirming = true
    } label: {
      HStack {
        Image(systemName: systemImage)
          .foregroundStyle(tint)
          .frame(width: 24)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
          if let detail {
            detail
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            ProgressView()
              .scaleEffect(0.6)
          }
        }
        Spacer()
        if isBusy {
          ProgressView()
            .scaleEffect(0.8)
        } else {
          Text(actionTitle)
            .font(.subheadline)
            .foregroundStyle(actionTint)
        }
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
    .confirmationDialog(
      confirmationTitle,
      isPresented: $isConfirming,
      titleVisibility: .visible
    ) {
      Button(confirmButtonTitle, role: .destructive, action: onConfirm)
    } message: {
      Text(confirmationMessage)
    }
  }
}
