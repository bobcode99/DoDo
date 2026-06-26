//
//  QuotesFinder.swift
//  PodcastAnalyzer
//
//  Locates AI-returned "Notable Quote" strings inside the timestamped
//  transcript so we can populate MM:SS / H:MM:SS markers without paying
//  the prompt-token cost of sending a timestamped transcript to the model.
//
//  Strategy (cheap, deterministic, no extra dependencies):
//    1. Normalize the quote and each segment (lowercase, strip punctuation,
//       collapse whitespace) so paraphrased capitalisation / punctuation
//       differences don't block a match.
//    2. Look for a substring match in a concatenated normalized transcript,
//       carrying a per-character map back to the originating segment.
//    3. If no substring match (the model paraphrased), fall back to
//       token-overlap scoring across all segments and pick the highest.
//

import Foundation

nonisolated struct QuotesFinder {
    /// Lightweight segment view so callers don't need to share a full model type.
    struct Segment {
        let startTime: TimeInterval
        let text: String
    }

    /// Enrich quotes with timestamps derived from `segments`.
    /// Quotes that already carry a timestamp are returned unchanged.
    /// Quotes that can't be matched keep `timestamp = nil`.
    static func enrich(
        quotes: [TimestampedQuote],
        segments: [Segment]
    ) -> [TimestampedQuote] {
        guard !segments.isEmpty else { return quotes }

        let index = NormalizedIndex(segments: segments)

        return quotes.map { quote in
            if let existing = quote.timestamp, !existing.isEmpty {
                return quote
            }
            guard let segment = index.bestMatch(for: quote.text) else {
                return quote
            }
            return TimestampedQuote(
                text: quote.text,
                timestamp: formatTimestamp(segment.startTime)
            )
        }
    }

    // MARK: - Formatting

    private static func formatTimestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Index

    /// Builds a normalized search index over the segments. Concatenated text
    /// is held alongside a per-character "owning segment" map for O(quote × N)
    /// substring scans, and a per-segment token set for the fallback path.
    private struct NormalizedIndex {
        let segments: [Segment]
        let concatenated: String
        /// For each character index in `concatenated`, the index in `segments`
        /// that contributed it. -1 marks the separator between two segments.
        let ownership: [Int]
        let segmentTokens: [Set<String>]

        init(segments: [Segment]) {
            self.segments = segments

            var pieces: [String] = []
            var owner: [Int] = []
            var tokens: [Set<String>] = []
            pieces.reserveCapacity(segments.count)
            tokens.reserveCapacity(segments.count)

            for (idx, segment) in segments.enumerated() {
                let normalized = Self.normalize(segment.text)
                if !pieces.isEmpty {
                    owner.append(-1) // separator
                }
                owner.append(contentsOf: Array(repeating: idx, count: normalized.count))
                pieces.append(normalized)
                tokens.append(
                    Set(
                        normalized
                            .split(separator: " ")
                            .map(String.init)
                            .filter { $0.count >= 4 }
                    )
                )
            }

            self.concatenated = pieces.joined(separator: " ")
            self.ownership = owner
            self.segmentTokens = tokens
        }

        func bestMatch(for quote: String) -> Segment? {
            let normalized = Self.normalize(quote)
            guard !normalized.isEmpty else { return nil }

            // Try progressively shorter prefixes — the model often shortens
            // or trims the quote. Anything under ~24 chars risks false hits.
            let prefixes = [60, 40, 24]
            for length in prefixes {
                guard normalized.count >= length else { continue }
                let needle = String(normalized.prefix(length))
                if let segment = scanSubstring(needle) {
                    return segment
                }
            }
            // Whole-quote substring (in case quote ≤ 24 chars)
            if normalized.count < 24, let segment = scanSubstring(normalized) {
                return segment
            }

            return tokenOverlapMatch(for: normalized)
        }

        private func scanSubstring(_ needle: String) -> Segment? {
            guard let range = concatenated.range(of: needle) else { return nil }
            let startCharIndex = concatenated.distance(from: concatenated.startIndex, to: range.lowerBound)
            guard startCharIndex < ownership.count else { return nil }
            // Walk forward through separator characters until we find a real owner.
            var idx = startCharIndex
            while idx < ownership.count, ownership[idx] == -1 {
                idx += 1
            }
            guard idx < ownership.count else { return nil }
            let segmentIdx = ownership[idx]
            guard segmentIdx >= 0, segmentIdx < segments.count else { return nil }
            return segments[segmentIdx]
        }

        private func tokenOverlapMatch(for normalizedQuote: String) -> Segment? {
            let quoteTokens = Set(
                normalizedQuote
                    .split(separator: " ")
                    .map(String.init)
                    .filter { $0.count >= 4 }
            )
            guard !quoteTokens.isEmpty else { return nil }

            var bestIndex: Int?
            var bestScore = 0

            for (idx, tokens) in segmentTokens.enumerated() {
                let overlap = quoteTokens.intersection(tokens).count
                if overlap > bestScore {
                    bestScore = overlap
                    bestIndex = idx
                }
            }

            // Require at least two overlapping tokens to call it a match.
            guard let idx = bestIndex, bestScore >= 2 else { return nil }
            return segments[idx]
        }

        /// Lowercase, strip diacritics, replace non-alphanumeric with a space,
        /// then collapse runs of whitespace. Cheap and good enough for English
        /// + CJK quotes.
        static func normalize(_ text: String) -> String {
            let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            var scalars = String.UnicodeScalarView()
            scalars.reserveCapacity(folded.unicodeScalars.count)
            for scalar in folded.unicodeScalars {
                if CharacterSet.alphanumerics.contains(scalar) {
                    scalars.append(scalar)
                } else {
                    scalars.append(" ")
                }
            }
            let collapsed = String(scalars)
                .split(separator: " ", omittingEmptySubsequences: true)
                .joined(separator: " ")
            return collapsed
        }
    }
}
