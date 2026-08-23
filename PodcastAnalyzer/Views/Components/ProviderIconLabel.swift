//
//  ProviderIconLabel.swift
//  PodcastAnalyzer
//
//  A Label that shows a provider's own brand mark instead of a generic
//  SF Symbol, so users can recognize OpenAI/Claude/Gemini/etc. at a glance.
//

import SwiftUI

struct ProviderIconLabel: View {
    let provider: CloudAIProvider
    var iconSize: CGFloat = 16

    var body: some View {
        Label {
            Text(provider.displayName)
        } icon: {
            if let assetName = provider.brandAssetName {
                Image(assetName)
                    .resizable()
                    .renderingMode(provider.brandAssetRendersOriginalColor ? .original : .template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
            } else {
                Image(systemName: provider.iconName)
            }
        }
    }
}
