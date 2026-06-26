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
        #if os(macOS)
        WrappingAttributedTextView(attributedString: displayAttributedString)
            .frame(maxWidth: .infinity, alignment: .leading)
        #else
        if let swiftAttributedString = convertToSwiftAttributedString() {
            Text(swiftAttributedString)
                .tint(.blue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(attributedString.string)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        #endif
    }

    #if os(macOS)
    private var displayAttributedString: NSAttributedString {
        let source: NSAttributedString
        if linkTimestamps, let swiftAttributedString = convertToSwiftAttributedString() {
            source = NSAttributedString(TimestampUtils.addTimestampLinks(to: swiftAttributedString))
        } else {
            source = attributedString
        }

        let result = NSMutableAttributedString(attributedString: source)
        let fullRange = NSRange(location: 0, length: result.length)

        result.enumerateAttribute(.foregroundColor, in: fullRange) { _, range, _ in
            result.removeAttribute(.foregroundColor, range: range)
        }

        result.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
        result.addAttribute(.font, value: NSFont.systemFont(ofSize: NSFont.systemFontSize), range: fullRange)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byCharWrapping
        paragraphStyle.lineSpacing = 2
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

        return result
    }
    #endif

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

#if os(macOS)
private struct WrappingAttributedTextView: NSViewRepresentable {
    let attributedString: NSAttributedString

    func makeNSView(context: Context) -> SelfSizingTextView {
        let textView = SelfSizingTextView(frame: .zero)
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = .zero
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineBreakMode = .byCharWrapping
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.linkTextAttributes = [.foregroundColor: NSColor.systemBlue]
        return textView
    }

    func updateNSView(_ nsView: SelfSizingTextView, context: Context) {
        nsView.textStorage?.setAttributedString(attributedString)
        nsView.invalidateIntrinsicContentSize()
    }
}

private final class SelfSizingTextView: NSTextView {
    override var frame: NSRect {
        didSet {
            if oldValue.size.width != frame.size.width {
                invalidateIntrinsicContentSize()
            }
        }
    }

    override var intrinsicContentSize: NSSize {
        guard let textContainer, let layoutManager else {
            return super.intrinsicContentSize
        }

        let width = max(bounds.width, 1)
        textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)

        let usedRect = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(usedRect.height))
    }
}
#endif
