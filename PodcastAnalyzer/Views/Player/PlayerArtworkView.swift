import SwiftUI

struct PlayerArtworkView: View {
    let imageURL: URL?
    let isPlaying: Bool

    var size: CGFloat = 280
    private let playingScale: CGFloat = 1.08

    var body: some View {
        if let imageURL {
            CachedAsyncImage(url: imageURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.3)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 60))
                            .foregroundStyle(.white.opacity(0.5))
                    )
            }
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: 16))
            .shadow(
                color: .black.opacity(isPlaying ? 0.4 : 0.25),
                radius: isPlaying ? 25 : 15,
                x: 0,
                y: isPlaying ? 12 : 8
            )
            .scaleEffect(isPlaying ? playingScale : 1.0)
            .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0), value: isPlaying)
        } else {
            Color.gray.opacity(0.3)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 60))
                        .foregroundStyle(.white.opacity(0.5))
                )
                .frame(width: size, height: size)
                .clipShape(.rect(cornerRadius: 16))
                .scaleEffect(isPlaying ? playingScale : 1.0)
                .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0), value: isPlaying)
        }
    }
}
