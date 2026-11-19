//
//  PosterImage.swift
//  CineMatch
//

import SwiftUI

/// Filmplakat fra TMDB. Fylder den plads, den får (beskåret), og viser en pladsholder,
/// mens den hentes, eller hvis der ingen plakat er. Kalderen sætter størrelse og hjørner.
///
/// Plakater gemmes i `PosterCache`, så en plakat, der er hentet i forvejen, vises med det samme.
struct PosterImage: View {
    let url: URL?

    /// Plakaten, når den er hentet. Gemmer URL'en med, så en gammel plakat ikke vises på et nyt kort.
    @State private var loaded: Loaded?

    private struct Loaded {
        let url: URL
        let image: UIImage
    }

    var body: some View {
        // Color.clear tager præcis den foreslåede størrelse, så billedet ikke vokser ud over rammen.
        Color.clear
            .overlay {
                if let image = currentImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    placeholder
                }
            }
            .clipped()
            .accessibilityHidden(true)
            .task(id: url) {
                guard let url, PosterCache.shared.cachedImage(for: url) == nil else { return }
                guard let image = await PosterCache.shared.image(for: url) else { return }
                withAnimation(.easeOut(duration: 0.2)) { loaded = Loaded(url: url, image: image) }
            }
    }

    private var currentImage: UIImage? {
        guard let url else { return nil }
        if let loaded, loaded.url == url { return loaded.image }
        return PosterCache.shared.cachedImage(for: url)
    }

    private var placeholder: some View {
        ZStack {
            Theme.gradient
            Image(systemName: "film")
                .font(.title)
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

#Preview {
    PosterImage(url: nil)
        .frame(width: 120, height: 180)
        .clipShape(.rect(cornerRadius: 8))
}
