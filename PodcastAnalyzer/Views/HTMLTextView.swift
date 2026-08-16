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
    /// Truncate after this many lines; `nil` shows the whole thing.
    ///
    /// A parameter rather than SwiftUI's `.lineLimit()`, which only applies to
    /// `Text` and is silently ignored by the text views below.
    var lineLimit: Int? = nil

    /// Forwarded to the text view's delegate so link taps keep flowing through
    /// whatever `OpenURLAction` the host installed — a UIKit/AppKit text view
    /// does not route them through SwiftUI on its own.
    @Environment(\.openURL) private var openURL

    var body: some View {
        #if os(macOS)
        WrappingAttributedTextView(
            attributedString: displayAttributedString, lineLimit: lineLimit, openURL: openURL
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        #else
        SelectableAttributedTextView(
            attributedString: displayAttributedString, lineLimit: lineLimit, openURL: openURL
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }

    /// Both platforms render the same string: timestamps linked if asked, the
    /// parser's baked-in colors stripped so the text follows the system label
    /// color, and a shared paragraph style.
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

        // Dynamic colors, not resolved ones: the text view re-draws them itself
        // when the appearance flips, with no re-render on our side.
        #if os(macOS)
        result.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
        result.addAttribute(.font, value: NSFont.systemFont(ofSize: NSFont.systemFontSize), range: fullRange)
        #else
        result.addAttribute(.foregroundColor, value: UIColor.label, range: fullRange)
        #endif

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byCharWrapping
        paragraphStyle.lineSpacing = 2
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

        return result
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
        return result
    }
}

// MARK: - Link forwarding

/// Hands link taps back to the SwiftUI `OpenURLAction` the host installed.
/// Shared by both platforms' text views.
private final class TextViewLinkCoordinator: NSObject {
    var openURL: OpenURLAction

    init(openURL: OpenURLAction) {
        self.openURL = openURL
    }
}

#if os(iOS)

// MARK: - iOS

/// A non-scrolling `UITextView`, which is what gives the description real text
/// selection — drag handles and partial ranges. SwiftUI's `Text` only offers
/// long-press-copy-everything, however `.textSelection(.enabled)` is applied.
private struct SelectableAttributedTextView: UIViewRepresentable {
    let attributedString: NSAttributedString
    let lineLimit: Int?
    let openURL: OpenURLAction

    func makeCoordinator() -> TextViewLinkCoordinator {
        TextViewLinkCoordinator(openURL: openURL)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        // Turning scrolling off is what makes a UITextView report a real
        // intrinsicContentSize — the host ScrollView does the scrolling.
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.linkTextAttributes = [.foregroundColor: UIColor.systemBlue]
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.openURL = openURL
        uiView.textStorage.setAttributedString(attributedString)
        // 0 means "no limit" to TextKit. The truncating line break mode belongs
        // on the container, not the paragraph style — on the paragraph style it
        // would clip every line instead of the last visible one.
        uiView.textContainer.maximumNumberOfLines = lineLimit ?? 0
        uiView.textContainer.lineBreakMode = lineLimit == nil ? .byWordWrapping : .byTruncatingTail
        uiView.invalidateIntrinsicContentSize()
    }

    /// Measured rather than left to `intrinsicContentSize`, which reports a
    /// stale height for the width SwiftUI is actually proposing — the collapsed
    /// →expanded switch came back a line short and the "Show less" button
    /// landed on top of the last line.
    func sizeThatFits(
        _ proposal: ProposedViewSize, uiView: UITextView, context: Context
    ) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitted.height))
    }
}

extension TextViewLinkCoordinator: UITextViewDelegate {
    func textView(
        _ textView: UITextView,
        primaryActionFor textItem: UITextItem,
        defaultAction: UIAction
    ) -> UIAction? {
        guard case .link(let url) = textItem.content else { return defaultAction }
        let openURL = self.openURL
        return UIAction { _ in openURL(url) }
    }
}

#else

// MARK: - macOS

private struct WrappingAttributedTextView: NSViewRepresentable {
    let attributedString: NSAttributedString
    let lineLimit: Int?
    let openURL: OpenURLAction

    func makeCoordinator() -> TextViewLinkCoordinator {
        TextViewLinkCoordinator(openURL: openURL)
    }

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
        textView.delegate = context.coordinator
        return textView
    }

    func updateNSView(_ nsView: SelfSizingTextView, context: Context) {
        context.coordinator.openURL = openURL
        nsView.textStorage?.setAttributedString(attributedString)
        // 0 means "no limit" to TextKit — see the iOS counterpart.
        nsView.textContainer?.maximumNumberOfLines = lineLimit ?? 0
        nsView.textContainer?.lineBreakMode = lineLimit == nil ? .byCharWrapping : .byTruncatingTail
        nsView.invalidateIntrinsicContentSize()
    }
}

extension TextViewLinkCoordinator: NSTextViewDelegate {
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let url: URL? = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
        guard let url else { return false }
        openURL(url)
        return true
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
