//
//  ExtensionView.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//
import Foundation
import SwiftUI

extension View {
  @ViewBuilder
  func iosNavigationBarTitleDisplayModeInline() -> some View {
    #if os(iOS)
      self.navigationBarTitleDisplayMode(.inline)
    #else
      self  // Do nothing on macOS
    #endif
  }

}
