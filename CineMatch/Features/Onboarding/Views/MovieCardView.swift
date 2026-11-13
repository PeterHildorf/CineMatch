//
//  MovieCardView.swift
//  CineMatch
//

import SwiftUI

/// Ét filmkort i onboarding: plakat, titel, år, genrer, instruktør og handling.
struct MovieCardView: View {
    let title: Title
    /// Plakat fra TMDB. Uden plakat vises en lav, farvet pladsholder.
    var posterURL: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let posterURL {
                PosterImage(url: posterURL)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PosterImage(url: nil)
                    .frame(height: 140)
                    .clipShape(.rect(cornerRadius: 12))
            }

            Text(title.title)
                .font(.title2.bold())
                .lineLimit(2)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let director = title.director {
                Text("Directed by \(director)")
                    .font(.subheadline)
            }

            if let overview = title.overview {
                Text(overview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(posterURL == nil ? 6 : 3)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.quaternary))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = title.year > 0 ? [String(title.year)] : []   // år 0 = ukendt
        if let runtime = title.runtimeMinutes { parts.append("\(runtime) min") }
        if !title.genres.isEmpty { parts.append(title.genres.prefix(3).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    MovieCardView(title: Title(
        id: 1, tmdbId: nil, title: "Se7en", year: 1995, genres: ["Crime", "Mystery", "Thriller"],
        director: "David Fincher",
        overview: "Two homicide detectives are on a desperate hunt for a serial killer.",
        runtimeMinutes: 127
    ))
    .frame(height: 480)
    .padding()
}
