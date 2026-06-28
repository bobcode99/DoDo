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
            let isMarker = MusicDetectionService.isMarker(segment.text)
            let hasTimeGap = group.last.map {
                segment.startTime - $0.endTime > gapThreshold
            } ?? false

            // Music markers always stand alone; flush any in-progress
            // sentence before appending the marker.
            if hasTimeGap || (isMarker && !group.isEmpty) {
                flush()
            }

            let trimmed = segment.text.trimmingCharacters(in: .whitespaces)
            group.append(segment)
            charCount += trimmed.count
            if !groupIsCJK { groupIsCJK = CJKTextUtils.containsCJK(trimmed) }

            // After appending a marker, close it out so it forms a
            // single-segment "sentence" on its own line.
            if isMarker {
                flush()
                continue
            }

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

// MARK: - Active-Sentence Lookup

extension Array where Element == TranscriptSentence {
    /// Id of the last sentence whose `startTime ≤ time`. O(log n) binary search.
    /// Returns nil when `time` precedes the first sentence's start, or runs
    /// `pastEndGrace` seconds beyond the final sentence's `endTime` — past that
    /// point the audio is untranscribed outro / credits / trailing ads, so the
    /// highlight should clear instead of pinning the last sentence lit.
    /// This is the single source of truth for "which sentence is playing".
    func activeID(at time: TimeInterval, pastEndGrace: TimeInterval = 5) -> Int? {
        guard !isEmpty, self[0].startTime <= time else { return nil }
        if let last, time > last.endTime + pastEndGrace { return nil }
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
        return self[lo].id
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

/// Renders a list of sentence blocks. Computes the active sentence from
/// `currentTime` (last-started semantics) and paints the search-result
/// flash overlay at this level so `SentenceView` itself stays static.
struct SentenceBasedTranscriptView: View {
    let sentences: [TranscriptSentence]
    let currentTime: TimeInterval?
    let searchQuery: String
    let onSegmentTap: (TranscriptSegment) -> Void

    var showTimestamps: Bool = false
    var subtitleMode: SubtitleDisplayMode = .originalOnly
    /// Sentence picked from the search sheet — pulsed for ~1s so the user
    /// can spot it after dismiss clears the active search query.
    var flashedSentenceID: Int?

    private var activeSentenceID: Int? {
        guard let t = currentTime else { return nil }
        return sentences.activeID(at: t)
    }

    /// Active segment index *within* the given sentence, or nil if this is not
    /// the active sentence (so non-active sentences don't have a "highlighted
    /// word" — keeps karaoke confined to one row at a time).
    ///
    /// When the row IS active but `currentTime` resolves to a value before
    /// this sentence's first segment (can happen when the sticky cache holds
    /// a forward sentence id while the live time briefly rubber-bands back),
    /// we still return `0` instead of `nil` — otherwise the user perceives
    /// the karaoke as "broken" on the row they know is currently playing.
    private func activeSegmentIndex(for sentence: TranscriptSentence, isActive: Bool) -> Int? {
        guard isActive else { return nil }
        guard let t = currentTime else { return 0 }
        return sentence.activeSegmentIndex(at: t) ?? 0
    }

    var body: some View {
        let activeID = activeSentenceID
        LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(sentences) { sentence in
                let isActive = sentence.id == activeID
                SentenceView(
                    sentence: sentence,
                    isActive: isActive,
                    activeSegmentIndex: activeSegmentIndex(for: sentence, isActive: isActive),
                    isFlashing: sentence.id == flashedSentenceID,
                    searchQuery: searchQuery,
                    subtitleMode: subtitleMode,
                    showTimestamp: showTimestamps,
                    onSegmentTap: onSegmentTap
                )
                .equatable()
                .id(sentence.id)
            }
        }
        .scrollTargetLayout()
    }
}

// MARK: - Sentence View

/// One sentence block. Tap anywhere on the row to seek to its start.
///
/// Karaoke highlight (active word in blue) is rendered by attributing a
/// `foregroundColor` range on an `AttributedString` — *only* the color
/// attribute changes between frames, never the font or weight, so glyph
/// metrics stay identical and the text never reflows.
struct SentenceView: View, Equatable {
    let sentence: TranscriptSentence
    let isActive: Bool
    /// Index of the active segment within `sentence.segments`. Nil for
    /// non-active sentences or when the playhead is before this sentence.
    let activeSegmentIndex: Int?
    /// Pulsed yellow tint when the user picks this sentence from search.
    /// Parent drives the clear via `withAnimation`, which lets the fade-out
    /// transition through this view's transaction without needing a row-level
    /// `.animation(_:value:)` modifier — that modifier was the source of a
    /// layout-shimmer bug because it swept up unrelated karaoke updates.
    let isFlashing: Bool
    let searchQuery: String
    let subtitleMode: SubtitleDisplayMode
    var showTimestamp: Bool = false
    let onSegmentTap: (TranscriptSegment) -> Void

    static func == (lhs: SentenceView, rhs: SentenceView) -> Bool {
        lhs.sentence.id == rhs.sentence.id &&
        lhs.sentence.endTime == rhs.sentence.endTime &&
        lhs.sentence.translatedText == rhs.sentence.translatedText &&
        lhs.isActive == rhs.isActive &&
        lhs.activeSegmentIndex == rhs.activeSegmentIndex &&
        lhs.isFlashing == rhs.isFlashing &&
        lhs.searchQuery == rhs.searchQuery &&
        lhs.subtitleMode == rhs.subtitleMode &&
        lhs.showTimestamp == rhs.showTimestamp
    }

    private var primaryShowsOriginal: Bool {
        switch subtitleMode {
        case .originalOnly, .dualOriginalFirst: true
        case .translatedOnly, .dualTranslatedFirst: false
        }
    }

    private var primaryText: String {
        primaryShowsOriginal ? sentence.text : (sentence.translatedText ?? sentence.text)
    }

    private var secondaryText: String? {
        switch subtitleMode {
        case .originalOnly, .translatedOnly:
            nil
        case .dualOriginalFirst:
            sentence.translatedText
        case .dualTranslatedFirst:
            sentence.translatedText != nil ? sentence.text : nil
        }
    }

    var body: some View {
        Button {
            if let first = sentence.segments.first {
                onSegmentTap(first)
            }
        } label: {
            HStack(alignment: .top, spacing: showTimestamp ? 12 : 0) {
                if showTimestamp {
                    Text(sentence.formattedStartTime)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isActive ? Color.blue : Color.secondary)
                        .frame(width: 50, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 4) {
                    primaryTextView
                    if let secondary = secondaryText {
                        Text(secondary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(isActive ? 0.08 : 0))
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.yellow.opacity(isFlashing ? 0.35 : 0))
            }
        }
    }

    @ViewBuilder
    private var primaryTextView: some View {
        if !searchQuery.isEmpty {
            SearchHighlightedText(text: primaryText, query: searchQuery)
                .font(.system(size: 17))
                .lineSpacing(4)
                .foregroundStyle(isActive ? Color.blue : Color.primary)
        } else if primaryShowsOriginal {
            // Always render via AttributedString so flipping isActive doesn't
            // swap between Text(String) and Text(AttributedString) variants.
            Text(karaokeAttributedString())
                .font(.system(size: 17))
                .lineSpacing(4)
                .foregroundStyle(Color.primary)
        } else {
            // Translation mode: no per-segment timing, so no karaoke.
            Text(primaryText)
                .font(.system(size: 17))
                .lineSpacing(4)
                .foregroundStyle(isActive ? Color.blue : Color.primary)
        }
    }

    /// Builds the primary text as an `AttributedString` where only the
    /// active segment range carries a `foregroundColor = .blue` attribute.
    /// Character content matches `sentence.text` exactly, so toggling the
    /// color attribute never reflows the line.
    private func karaokeAttributedString() -> AttributedString {
        var result = AttributedString()
        var first = true
        var prevEndIsCJK = false

        for (i, seg) in sentence.segments.enumerated() {
            let raw = seg.text.trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { continue }

            let nextStartIsCJK = raw.unicodeScalars.first.map { CJKTextUtils.isCJKScalar($0) } ?? false
            if !first && !prevEndIsCJK && !nextStartIsCJK {
                result.append(AttributedString(" "))
            }

            var piece = AttributedString(raw)
            if i == activeSegmentIndex {
                piece.foregroundColor = .blue
            }
            result.append(piece)

            prevEndIsCJK = raw.unicodeScalars.last.map { CJKTextUtils.isCJKScalar($0) } ?? false
            first = false
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
                            subtitleMode: effectiveDisplayMode
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
