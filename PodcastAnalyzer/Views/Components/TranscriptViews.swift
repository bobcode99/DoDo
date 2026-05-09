//
//  TranscriptViews.swift
//  PodcastAnalyzer
//
//  Sentence-block transcript display with per-segment highlighting.
//
//  Architecture (single source of truth):
//  - Raw SRT segments are grouped once by `TranscriptGrouping.groupIntoSentences`
//    using sentence-ending punctuation, time gaps, and a CJK/Latin soft cap.
//  - Each sentence keeps the id of its first segment (stable across regroup).
//  - The view computes the active sentence as `sentences.last { startTime ≤ time }`
//    (last-started semantics) and the active segment within it the same way.
//

import SwiftUI

// MARK: - Sentence Model

/// A sentence-block composed of one or more SRT segments.
struct TranscriptSentence: Identifiable {
    /// Stable id = first segment's id. Survives regrouping.
    let id: Int
    let segments: [TranscriptSegment]

    var startTime: TimeInterval { segments.first?.startTime ?? 0 }
    var endTime: TimeInterval { segments.last?.endTime ?? 0 }
    var formattedStartTime: String { segments.first?.formattedStartTime ?? "0:00" }

    /// Combined original text with CJK-aware spacing.
    var text: String {
        CJKTextUtils.joinTexts(segments.map { $0.text.trimmingCharacters(in: .whitespaces) })
    }

    /// Combined translated text. Returns nil unless every segment has a translation.
    var translatedText: String? {
        let parts = segments.compactMap { $0.translatedText?.trimmingCharacters(in: .whitespaces) }
        guard parts.count == segments.count else { return nil }
        return CJKTextUtils.joinTexts(parts)
    }

    /// Index of the active segment at `time` using last-started semantics.
    /// A segment becomes active at its `startTime` and stays active until the
    /// next segment's `startTime`. Returns nil if `time < startTime`.
    func activeSegmentIndex(at time: TimeInterval) -> Int? {
        segments.indices.last { segments[$0].startTime <= time }
    }
}

// MARK: - Sentence Grouping

enum TranscriptGrouping {
    /// Sentence terminators (Latin + CJK).
    private static let sentenceEndings: Set<Character> = [".", "!", "?", "\u{3002}", "\u{FF01}", "\u{FF1F}"]

    /// CJK clause-level punctuation. When a sentence is over the soft cap but
    /// the next segment opens with one of these, defer the flush — the next cue
    /// is mid-clause and breaking here would split a phrase.
    private static let cjkClauseContinuations: Set<Character> = [
        "\u{FF0C}", "\u{3001}", "\u{FF1B}", "\u{FF1A}",  // ， 、 ； ：
        ",", ";", ":",
    ]

    /// Force a sentence break when consecutive segments are separated by more
    /// than this many seconds (music interludes, long pauses).
    static let gapThreshold: TimeInterval = 2.0

    /// Soft character cap for CJK content. CJK glyphs render wider per character,
    /// and tighter blocks read better.
    static let cjkSoftCap = 30

    /// Soft character cap for Latin content. Roughly one phone-screen line.
    static let latinSoftCap = 80

    /// Hard ceiling — never let a sentence run past this even if look-ahead
    /// would otherwise extend it.
    static let cjkHardCap = 60
    static let latinHardCap = 160

    /// Group raw SRT segments into sentence blocks.
    /// Splits at: sentence-ending punctuation, time gap > `gapThreshold`,
    /// or the soft cap (with look-ahead deferral up to the hard cap).
    static func groupIntoSentences(_ segments: [TranscriptSegment]) -> [TranscriptSentence] {
        var sentences: [TranscriptSentence] = []
        var group: [TranscriptSegment] = []
        var charCount = 0
        var groupIsCJK = false

        func flush() {
            guard let first = group.first else { return }
            sentences.append(TranscriptSentence(id: first.id, segments: group))
            group = []
            charCount = 0
            groupIsCJK = false
        }

        /// True when the next segment opens mid-clause — i.e. with whitespace,
        /// a continuation comma, or (for Latin) a non-alphanumeric. Splitting
        /// just before that produces an awkward "...end" / ", continuation" pair.
        func nextIsMidClause(_ index: Int) -> Bool {
            guard index + 1 < segments.count else { return false }
            let next = segments[index + 1].text.trimmingCharacters(in: .whitespaces)
            guard let first = next.first else { return false }
            if cjkClauseContinuations.contains(first) { return true }
            if groupIsCJK { return false }
            // Latin: continuation if the next cue starts with a lowercase letter
            // or non-alphanumeric (matches AntennaPod's heuristic).
            return !first.isUppercase && !first.isNumber
        }

        for (i, segment) in segments.enumerated() {
            if let last = group.last,
               segment.startTime - last.endTime > gapThreshold {
                flush()
            }

            let trimmed = segment.text.trimmingCharacters(in: .whitespaces)
            group.append(segment)
            charCount += trimmed.count
            if !groupIsCJK { groupIsCJK = CJKTextUtils.containsCJK(trimmed) }

            let softCap = groupIsCJK ? cjkSoftCap : latinSoftCap
            let hardCap = groupIsCJK ? cjkHardCap : latinHardCap
            let endsSentence = trimmed.last.map { sentenceEndings.contains($0) } ?? false

            if endsSentence || charCount >= hardCap {
                flush()
            } else if charCount >= softCap && !nextIsMidClause(i) {
                flush()
            }
        }
        flush()
        return sentences
    }
}

// MARK: - Binary-Search Helpers

extension Array where Element == TranscriptSentence {
    /// Last sentence whose `startTime ≤ time`, found via binary search. O(log n).
    /// Mirrors AntennaPod's `Transcript.findSegmentIndexBefore`.
    func index(at time: TimeInterval) -> Int? {
        guard !isEmpty, self[0].startTime <= time else { return nil }
        var lo = 0
        var hi = count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if self[mid].startTime > time {
                hi = mid - 1
            } else {
                lo = mid
            }
        }
        return lo
    }

    /// Convenience: id of the active sentence at `time`, or nil.
    func activeID(at time: TimeInterval) -> Int? {
        index(at: time).map { self[$0].id }
    }
}

// MARK: - CJK Text Utilities

nonisolated enum CJKTextUtils {
    private static let cjkRanges: [ClosedRange<UInt32>] = [
        0x4E00...0x9FFF,
        0x3400...0x4DBF,
        0x20000...0x2A6DF,
        0x2A700...0x2B73F,
        0x2B740...0x2B81F,
        0x3040...0x309F,
        0x30A0...0x30FF,
        0xAC00...0xD7AF,
        0x1100...0x11FF,
    ]

    static func containsCJK(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            for range in cjkRanges where range.contains(scalar.value) {
                return true
            }
        }
        return false
    }

    static func tokenize(_ text: String) -> [String] {
        if containsCJK(text) {
            return text.map { String($0) }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        } else {
            return text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        }
    }

    static func isCJKScalar(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return cjkRanges.contains { $0.contains(value) }
    }

    /// Join text parts with CJK-aware spacing — no space when either side is CJK.
    static func joinTexts(_ texts: [String]) -> String {
        guard var result = texts.first else { return "" }
        for i in 1..<texts.count {
            let next = texts[i]
            guard !next.isEmpty else { continue }
            let prevEndIsCJK = result.unicodeScalars.last.map { isCJKScalar($0) } ?? false
            let nextStartIsCJK = next.unicodeScalars.first.map { isCJKScalar($0) } ?? false
            if !prevEndIsCJK && !nextStartIsCJK {
                result += " "
            }
            result += next
        }
        return result
    }
}

// MARK: - Segment Tap Links

nonisolated enum TranscriptSegmentLink {
    static let urlScheme = "pa-transcript-segment"

    static func url(for segment: TranscriptSegment) -> URL? {
        URL(string: "\(urlScheme)://\(segment.id)")
    }

    static func segmentID(from url: URL) -> Int? {
        guard url.scheme == urlScheme,
              let host = url.host(),
              let segmentID = Int(host) else { return nil }
        return segmentID
    }
}

// MARK: - Search Highlighted Text

struct SearchHighlightedText: View {
    let text: String
    let query: String

    var body: some View {
        Text(buildHighlightedAttributedString())
    }

    private func buildHighlightedAttributedString() -> AttributedString {
        guard !query.isEmpty else { return AttributedString(text) }

        var result = AttributedString()
        let lowercasedText = text.lowercased()
        let lowercasedQuery = query.lowercased()
        var currentIndex = text.startIndex

        while let range = lowercasedText[currentIndex...].range(of: lowercasedQuery) {
            let beforeRange = currentIndex..<range.lowerBound
            if !beforeRange.isEmpty {
                result.append(AttributedString(String(text[beforeRange])))
            }
            var highlighted = AttributedString(String(text[range]))
            highlighted.backgroundColor = .orange.opacity(0.35)
            highlighted.font = .system(size: 17, weight: .semibold)
            result.append(highlighted)
            currentIndex = range.upperBound
        }
        if currentIndex < text.endIndex {
            result.append(AttributedString(String(text[currentIndex...])))
        }
        return result
    }
}

// MARK: - Sentence-Based Transcript View

/// Renders a list of sentence blocks. Computes the active sentence/segment
/// from `currentTime` using last-started semantics.
struct SentenceBasedTranscriptView: View {
    let sentences: [TranscriptSentence]
    let currentTime: TimeInterval?
    let searchQuery: String
    let onSegmentTap: (TranscriptSegment) -> Void

    var showTimestamps: Bool = false
    var subtitleMode: SubtitleDisplayMode = .originalOnly
    var searchMatchIds: Set<Int> = []
    var currentSearchMatchId: Int?

    /// The single active sentence — the last one whose `startTime ≤ currentTime`.
    private var activeSentenceID: Int? {
        guard let t = currentTime else { return nil }
        return sentences.activeID(at: t)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(sentences) { sentence in
                let isActive = sentence.id == activeSentenceID
                let activeIdx = isActive
                    ? sentence.activeSegmentIndex(at: currentTime ?? 0)
                    : nil
                SentenceView(
                    sentence: sentence,
                    isActive: isActive,
                    activeSegmentIndex: activeIdx,
                    searchQuery: searchQuery,
                    subtitleMode: subtitleMode,
                    showTimestamp: showTimestamps,
                    isSearchMatch: searchMatchIds.contains(sentence.id),
                    isCurrentSearchMatch: currentSearchMatchId == sentence.id,
                    onSegmentTap: onSegmentTap
                )
                .equatable()
                .id(sentence.id)
            }
        }
    }
}

// MARK: - Sentence View

/// Displays one sentence block. Active segment within the active sentence is
/// rendered blue + semibold; already-spoken segments fade to secondary; upcoming
/// segments stay primary.
struct SentenceView: View, Equatable {
    let sentence: TranscriptSentence
    let isActive: Bool
    let activeSegmentIndex: Int?
    let searchQuery: String
    let subtitleMode: SubtitleDisplayMode
    var showTimestamp: Bool = false
    var isSearchMatch: Bool = false
    var isCurrentSearchMatch: Bool = false
    let onSegmentTap: (TranscriptSegment) -> Void

    static func == (lhs: SentenceView, rhs: SentenceView) -> Bool {
        lhs.sentence.id == rhs.sentence.id &&
        lhs.sentence.translatedText == rhs.sentence.translatedText &&
        lhs.isActive == rhs.isActive &&
        lhs.activeSegmentIndex == rhs.activeSegmentIndex &&
        lhs.searchQuery == rhs.searchQuery &&
        lhs.subtitleMode == rhs.subtitleMode &&
        lhs.showTimestamp == rhs.showTimestamp &&
        lhs.isSearchMatch == rhs.isSearchMatch &&
        lhs.isCurrentSearchMatch == rhs.isCurrentSearchMatch
    }

    private var supportsInlineSegmentLinks: Bool {
        searchQuery.isEmpty && !primaryIsTranslated
    }

    private var primaryText: String {
        switch subtitleMode {
        case .originalOnly, .dualOriginalFirst:
            return sentence.text
        case .translatedOnly, .dualTranslatedFirst:
            return sentence.translatedText ?? sentence.text
        }
    }

    private var primaryIsTranslated: Bool {
        switch subtitleMode {
        case .originalOnly, .dualOriginalFirst:
            return false
        case .translatedOnly, .dualTranslatedFirst:
            return sentence.translatedText != nil
        }
    }

    private var secondaryText: String? {
        switch subtitleMode {
        case .originalOnly, .translatedOnly:
            return nil
        case .dualOriginalFirst:
            return sentence.translatedText
        case .dualTranslatedFirst:
            return sentence.translatedText != nil ? sentence.text : nil
        }
    }

    var body: some View {
        Group {
            if supportsInlineSegmentLinks {
                sentenceRow
                    .environment(\.openURL, OpenURLAction { url in
                        guard let segmentID = TranscriptSegmentLink.segmentID(from: url),
                              let segment = sentence.segments.first(where: { $0.id == segmentID }) else {
                            return .systemAction
                        }
                        onSegmentTap(segment)
                        return .handled
                    })
            } else {
                Button {
                    if let firstSegment = sentence.segments.first {
                        onSegmentTap(firstSegment)
                    }
                } label: {
                    sentenceRow
                }
                .buttonStyle(.plain)
            }
        }
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.08))
            }
        }
    }

    @ViewBuilder
    private var sentenceRow: some View {
        HStack(alignment: .top, spacing: showTimestamp ? 12 : 0) {
            if showTimestamp {
                Text(sentence.formattedStartTime)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isActive ? .blue : .secondary)
                    .frame(width: 50, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 4) {
                buildSentenceText()
                    .font(.system(size: 17, weight: .regular))
                    .lineSpacing(4)

                if let secondary = secondaryText {
                    Text(secondary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private func buildSentenceText() -> some View {
        if !searchQuery.isEmpty {
            SearchHighlightedText(text: primaryText, query: searchQuery)
        } else if primaryIsTranslated {
            Text(buildPlainStyledText(primaryText))
        } else {
            Text(buildSegmentHighlightedAttributedString())
        }
    }

    /// Translated text doesn't have segment-level timing — render as one styled block.
    private func buildPlainStyledText(_ text: String) -> AttributedString {
        var attrText = AttributedString(text)
        if isActive {
            attrText.foregroundColor = .blue
            attrText.font = .system(size: 17, weight: .semibold)
        } else {
            attrText.foregroundColor = .primary
            attrText.font = .system(size: 17, weight: .regular)
        }
        return attrText
    }

    /// Inline segment-level highlighting for the original text.
    private func buildSegmentHighlightedAttributedString() -> AttributedString {
        var result = AttributedString()

        for (index, segment) in sentence.segments.enumerated() {
            let segmentText = segment.text.trimmingCharacters(in: .whitespaces)
            var attrText = AttributedString(segmentText)
            if let url = TranscriptSegmentLink.url(for: segment) {
                attrText.link = url
            }

            if isActive, let activeIdx = activeSegmentIndex {
                if index == activeIdx {
                    attrText.foregroundColor = .blue
                    attrText.font = .system(size: 17, weight: .semibold)
                } else if index < activeIdx {
                    attrText.foregroundColor = .secondary
                    attrText.font = .system(size: 17, weight: .regular)
                } else {
                    attrText.foregroundColor = .primary
                    attrText.font = .system(size: 17, weight: .regular)
                }
            } else {
                attrText.foregroundColor = .primary
                attrText.font = .system(size: 17, weight: .regular)
            }

            result.append(attrText)

            if index < sentence.segments.count - 1 {
                let nextText = sentence.segments[index + 1].text.trimmingCharacters(in: .whitespaces)
                let endIsCJK = segmentText.unicodeScalars.last.map { CJKTextUtils.isCJKScalar($0) } ?? false
                let startIsCJK = nextText.unicodeScalars.first.map { CJKTextUtils.isCJKScalar($0) } ?? false
                if !endIsCJK && !startIsCJK {
                    result.append(AttributedString(" "))
                }
            }
        }

        return result
    }
}

// MARK: - Search Navigation Bar

struct TranscriptSearchNavigationBar: View {
    let matchCount: Int
    let currentIndex: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(currentIndex + 1) of \(matchCount)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)

            Divider()
                .frame(height: 20)

            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .semibold))
            }
            .disabled(matchCount == 0)

            Button(action: onNext) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
            }
            .disabled(matchCount == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Full Transcript Sheet Content

/// Full-screen transcript sheet. Used by ExpandedPlayerView.
///
/// Sentences are passed in pre-grouped (cached on the VM) — we don't regroup
/// per body render. Search runs against the full sentence list and, to catch
/// queries that straddle a sentence boundary (common in CJK where there are
/// no word spaces), we also test each adjacent sentence pair as one joined string.
struct FullTranscriptContent: View {
    let sentences: [TranscriptSentence]
    let currentTime: TimeInterval?
    @Binding var searchQuery: String
    let onSegmentTap: (TranscriptSegment) -> Void

    private var settings: SubtitleSettingsManager { .shared }

    private var hasTranslation: Bool {
        sentences.contains { $0.translatedText != nil }
    }

    private var effectiveDisplayMode: SubtitleDisplayMode {
        let stored = settings.displayMode
        guard stored.requiresTranslation else { return stored }
        return hasTranslation ? stored : .originalOnly
    }

    private var activeSentenceID: Int? {
        guard let t = currentTime else { return nil }
        return sentences.activeID(at: t)
    }

    @State private var currentSearchIndex: Int = 0
    @State private var searchMatchIdsList: [Int] = []

    private func recomputeMatches(for query: String) {
        guard !query.isEmpty else {
            searchMatchIdsList = []
            currentSearchIndex = 0
            return
        }

        // Sentence-level matches.
        var matched = Set<Int>()
        var ordered: [Int] = []
        for sentence in sentences where sentence.text.localizedStandardContains(query) {
            if matched.insert(sentence.id).inserted {
                ordered.append(sentence.id)
            }
        }

        // Boundary-spanning matches: join each adjacent pair and test the joined
        // text. CJK-aware joining ensures e.g. "海峽過路" + "費用高達" matches "過路費".
        if sentences.count >= 2 {
            for i in 0..<(sentences.count - 1) {
                let a = sentences[i]
                let b = sentences[i + 1]
                if matched.contains(a.id) && matched.contains(b.id) { continue }
                let joined = CJKTextUtils.joinTexts([a.text, b.text])
                guard joined.localizedStandardContains(query) else { continue }
                // Confirm the match actually crosses the boundary — if it lives
                // entirely in `a` or `b` we already caught it above.
                if !a.text.localizedStandardContains(query) || !b.text.localizedStandardContains(query) {
                    if matched.insert(a.id).inserted { ordered.append(a.id) }
                    if matched.insert(b.id).inserted { ordered.append(b.id) }
                }
            }
            // Re-sort by appearance order in the transcript.
            let position = Dictionary(uniqueKeysWithValues: sentences.enumerated().map { ($1.id, $0) })
            ordered.sort { (position[$0] ?? 0) < (position[$1] ?? 0) }
        }

        searchMatchIdsList = ordered
        currentSearchIndex = 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
                TextField("Search transcript...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.platformSystemGray6)
            .clipShape(.rect(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollViewReader { proxy in
                ZStack(alignment: .bottom) {
                    ScrollView {
                        SentenceBasedTranscriptView(
                            sentences: sentences,
                            currentTime: currentTime,
                            searchQuery: searchQuery,
                            onSegmentTap: onSegmentTap,
                            showTimestamps: false,
                            subtitleMode: effectiveDisplayMode,
                            searchMatchIds: Set(searchMatchIdsList),
                            currentSearchMatchId: searchMatchIdsList.isEmpty ? nil : searchMatchIdsList[currentSearchIndex]
                        )
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .padding(.bottom, !searchQuery.isEmpty && !searchMatchIdsList.isEmpty ? 60 : 0)
                    }
                    .onChange(of: activeSentenceID) { _, newId in
                        if let id = newId, searchQuery.isEmpty {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }

                    if !searchQuery.isEmpty && !searchMatchIdsList.isEmpty {
                        TranscriptSearchNavigationBar(
                            matchCount: searchMatchIdsList.count,
                            currentIndex: currentSearchIndex,
                            onPrevious: {
                                currentSearchIndex = (currentSearchIndex - 1 + searchMatchIdsList.count) % searchMatchIdsList.count
                                withAnimation {
                                    proxy.scrollTo(searchMatchIdsList[currentSearchIndex], anchor: .center)
                                }
                            },
                            onNext: {
                                currentSearchIndex = (currentSearchIndex + 1) % searchMatchIdsList.count
                                withAnimation {
                                    proxy.scrollTo(searchMatchIdsList[currentSearchIndex], anchor: .center)
                                }
                            }
                        )
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .onAppear { recomputeMatches(for: searchQuery) }
        .onChange(of: searchQuery) { _, newQuery in
            recomputeMatches(for: newQuery)
        }
    }
}
