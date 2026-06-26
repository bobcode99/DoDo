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

    private var deltaText: String {
        let delta = abs(audioDuration - transcriptDuration)
        let which = audioDuration > transcriptDuration ? "audio longer" : "transcript longer"
        return "\(Formatters.formatPlaybackTime(delta)) \(which)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            Text("Audio and transcript lengths differ (\(deltaText)) — highlight may drift, possibly due to ads")
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
