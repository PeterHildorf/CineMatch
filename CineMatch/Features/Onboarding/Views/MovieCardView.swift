//
//  MovieCardView.swift
//  CineMatch
//

import SwiftUI

/// Ét filmkort i Swipe: plakaten fylder hele kortet, titel og år ligger oven på en mørk gradient.
/// Tryk på kortet viser handlingen (og skjuler den igen).
struct MovieCardView: View {
    let title: Title
    /// Plakat fra TMDB. Uden plakat vises en farvet pladsholder med titlen.
    var posterURL: URL? = nil

    @State private var isShowingDetails = false

    var body: some View {
        PosterImage(url: posterURL)
            .overlay(alignment: .bottom) { info }
            .clipShape(.rect(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.08)))
            .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
            .contentShape(.rect)
            .onTapGesture {
                withAnimation(.spring(duration: 0.3)) { isShowingDetails.toggle() }
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint(isShowingDetails ? "Tap to hide the plot" : "Tap to show the plot")
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.title)
                .font(.largeTitle.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.subheadline.weight(.medium))
                .opacity(0.85)

            if isShowingDetails {
                if let director = title.director {
                    Text("Directed by \(director)")
                        .font(.subheadline)
                }
                if let overview = title.overview {
                    Text(overview)
                        .font(.callout)
                        .opacity(0.9)
                        .lineLimit(6)
                }
            } else if title.overview != nil {
                Label("Tap for plot", systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .opacity(0.7)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .padding(.top, 60)
        .background {
            LinearGradient(
                colors: [.clear, .black.opacity(isShowingDetails ? 0.9 : 0.75)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private var subtitle: String {
        var parts = title.year > 0 ? [String(title.year)] : []   // år 0 = ukendt
        if let runtime = title.runtimeMinutes { parts.append("\(runtime) min") }
        if !title.genres.isEmpty { parts.append(title.genres.prefix(2).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    MovieCardView(title: DemoData.titles[0])
        .frame(height: 520)
        .padding()
}
