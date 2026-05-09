//
//  HTMLTextView.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/11/28.
//

import SwiftUI

struct HTMLTextView: View {
    let attributedString: NSAttributedString
    var linkTimestamps: Bool = false

    var body: some View {
        if let swiftAttributedString = convertToSwiftAttributedString() {
            Text(swiftAttributedString)
                .tint(.blue)
        } else {
            Text(attributedString.string)
        }
    }

    private func convertToSwiftAttributedString() -> AttributedString? {
        #if os(macOS)
        guard var result = try? AttributedString(attributedString, including: \.appKit) else { return nil }
        // Strip baked-in foreground colors so text inherits SwiftUI's adaptive .primary style
        for run in result.runs {
            result[run.range].appKit.foregroundColor = nil
        }
        #else
        guard var result = try? AttributedString(attributedString, including: \.uiKit) else { return nil }
        // Strip baked-in foreground colors so text inherits SwiftUI's adaptive .primary style
        for run in result.runs {
            result[run.range].uiKit.foregroundColor = nil
        }
        #endif
        if linkTimestamps {
            result = TimestampUtils.addTimestampLinks(to: result)
        }
        return result
    }
}
