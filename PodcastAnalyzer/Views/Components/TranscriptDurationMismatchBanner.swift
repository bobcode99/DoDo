//
//  TranscriptDurationMismatchBanner.swift
//  PodcastAnalyzer
//
//  Slim notice shown when the playing audio's duration differs materially from
//  the transcript's last timestamp. The usual cause is Dynamic Ad Insertion:
//  the mp3 being played was re-stitched with ads after the transcript was made,
//  so the karaoke highlight drifts further out of sync the longer it plays.
//

import SwiftUI

struct TranscriptDurationMismatchBanner: View {
    let audioDuration: TimeInterval
    let transcriptDuration: TimeInterval

    private var message: LocalizedStringResource {
        let delta = Formatters.formatPlaybackTime(abs(audioDuration - transcriptDuration))
        return audioDuration > transcriptDuration
            ? "Audio and transcript lengths differ (\(delta) audio longer) — highlight may drift, possibly due to ads"
            : "Audio and transcript lengths differ (\(delta) transcript longer) — highlight may drift, possibly due to ads"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }
}
