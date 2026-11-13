//
//  PosterImage.swift
//  CineMatch
//

import SwiftUI

/// Filmplakat fra TMDB. Fylder den plads, den får (beskåret), og viser en pladsholder,
/// mens den hentes, eller hvis der ingen plakat er. Kalderen sætter størrelse og hjørner.
struct PosterImage: View {
    let url: URL?

    var body: some View {
        // Color.clear tager præcis den foreslåede størrelse, så billedet ikke vokser ud over rammen.
        Color.clear
            .overlay {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
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
