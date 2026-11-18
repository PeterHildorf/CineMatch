//
//  RecommendationRow.swift
//  CineMatch
//

import SwiftUI

/// Ét anbefalingskort: placering, plakat, titel, år, begrundelse og streamingtjeneste.
struct RecommendationRow: View {
    let position: Int
    let item: RecommendationsViewModel.Item
    let myServices: Set<StreamingService>
    /// "Seen it" → brugerens dom. `nil` = knappen vises ikke.
    var onSeen: ((Verdict) -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(position)")
                .font(.title2.bold())
                .foregroundStyle(.secondary)
                .frame(minWidth: 22)

            PosterImage(url: item.media?.posterURL)
                .frame(width: 60, height: 90)
                .clipShape(.rect(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.headline)
                if let title = item.title {
                    Text(Self.subtitle(for: title))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let reason = item.recommendation.reason {
                    Text(reason)
                        .font(.callout)
                }
                if let media = item.media {
                    WhereToWatch(media: media, myServices: myServices)
                }
                if let onSeen {
                    VerdictMenu(onRate: onSeen)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        // Menuen er slået sammen med resten af rækken, så VoiceOver får den som handlinger i stedet.
        .accessibilityActions {
            if let onSeen {
                ForEach(Verdict.seenOptions.reversed()) { verdict in
                    Button("Seen it – \(verdict.label)") { onSeen(verdict) }
                }
            }
        }
    }

    /// "1999 · Action, Sci-Fi". År 0 = ukendt (nogle titler i Mikkels katalog) og vises ikke.
    static func subtitle(for title: Title) -> String {
        let genres = title.genres.prefix(3).joined(separator: ", ")
        guard title.year > 0 else { return genres }
        return "\(String(title.year)) · \(genres)"
    }
}

/// Hvor filmen kan ses. Brugerens egne tjenester vises først:
/// "✓ Netflix · in your subscription", ellers "Netflix · not in your services".
/// Leje og køb kaldes aldrig "in your subscription".
struct WhereToWatch: View {
    let media: TitleMedia
    let myServices: Set<StreamingService>

    var body: some View {
        Group {
            if let provider = media.provider(in: myServices) {
                HStack(spacing: 6) {
                    ProviderLogo(provider: provider)
                    Text("\(Image(systemName: "checkmark")) \(provider.name) · in your subscription")
                }
                .foregroundStyle(.green)
            } else if let provider = media.bestProvider {
                HStack(spacing: 6) {
                    ProviderLogo(provider: provider)
                    if myServices.isEmpty {
                        Text("Stream on \(provider.name)")
                            .foregroundStyle(.primary)
                    } else {
                        Text("\(provider.name) · not in your services")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if media.canRentOrBuy {
                Label("Rent or buy", systemImage: "cart")
                    .foregroundStyle(.secondary)
            } else {
                Label("Not streaming in your country", systemImage: "play.slash")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline.weight(.medium))
        .padding(.top, 2)
    }
}

private struct ProviderLogo: View {
    let provider: StreamingProvider

    var body: some View {
        AsyncImage(url: provider.logoURL) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Image(systemName: "play.tv")
        }
        .frame(width: 20, height: 20)
        .clipShape(.rect(cornerRadius: 4))
    }
}

#Preview {
    List {
        RecommendationRow(
            position: 1,
            item: RecommendationsViewModel.Item(
                recommendation: DemoData.recommendations[0],
                title: DemoData.titles.first { $0.id == DemoData.recommendations[0].movieID },
                media: DemoData.media[DemoData.recommendations[0].movieID]
            ),
            myServices: [.netflix],
            onSeen: { _ in }
        )
    }
}
