import SwiftUI

/// Immersive player background: the episode artwork scaled to fill and heavily
/// blurred so the player picks up the cover's colors, finished with a light
/// glass material for the iOS 26 frosted look and to keep controls legible.
/// Falls back to the neutral gradient when there is no artwork.
struct ArtworkBackgroundView: View {
    let imageURL: URL?

    var body: some View {
        ZStack {
            Color.platformBackground

            if let imageURL {
                CachedAsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.clear
                }
                .blur(radius: 60)

                // Dark scrim: keeps the cover's color vivid while guaranteeing
                // white controls stay legible even over a light artwork.
                LinearGradient(
                    colors: [.black.opacity(0.25), .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [Color.gray.opacity(0.3), Color.platformBackground],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.4), value: imageURL)
    }
}
