//
//  RecommendationsView.swift
//  CineMatch
//

import SwiftUI

/// Viser top 10 fra én model og knappen "Get recommendations".
struct RecommendationsView: View {
    let viewModel: RecommendationsViewModel

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView("Loading recommendations …")
            case .empty:
                ContentUnavailableView {
                    Label("No recommendations yet", systemImage: "sparkles")
                } description: {
                    // Fejl (fx for få likes) vises her, ellers en vejledning.
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else {
                        Text(viewModel.emptyHint)
                    }
                } actions: {
                    recomputeButton
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("Something went wrong", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await viewModel.load() } }
                }
            case .loaded(let items):
                recommendationList(items)
            }
        }
        .navigationTitle(viewModel.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Get recommendations", systemImage: "arrow.clockwise") {
                    Task { await viewModel.recompute() }
                }
                .disabled(viewModel.isRecomputing)
            }
        }
        // Mens modellen regner: lås knappen og vis en spinner.
        .overlay {
            if viewModel.isRecomputing {
                ProgressView("Finding movies for you …")
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
        }
        .task { await viewModel.load() }
    }

    private var recomputeButton: some View {
        Button("Get recommendations") {
            Task { await viewModel.recompute() }
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.isRecomputing)
    }

    private func recommendationList(_ items: [RecommendationsViewModel.Item]) -> some View {
        List {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if viewModel.canFilterByServices {
                Toggle("Only my services", isOn: Binding(
                    get: { viewModel.preferences.onlyMyServices },
                    set: { isOn in Task { await viewModel.setOnlyMyServices(isOn) } }
                ))
            }
            Section {
                if viewModel.isFiltering {
                    ProgressView("Checking your services …")
                }
                // Placering i den viste liste (1–10), ikke modellens rank – de er forskellige, når der filtreres.
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    RecommendationRow(position: index + 1, item: item, myServices: viewModel.myServices)
                }
                if let filterNote = viewModel.filterNote {
                    Text(filterNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                // TMDB og JustWatch kræver, at vi krediterer dem.
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB. Streaming data by JustWatch.")
            }
        }
        .refreshable { await viewModel.load() }
    }
}

/// Ét anbefalingskort: placering, plakat, titel, år, begrundelse og streamingtjeneste.
private struct RecommendationRow: View {
    let position: Int
    let item: RecommendationsViewModel.Item
    let myServices: Set<StreamingService>

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
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// "1999 · Action, Sci-Fi". År 0 = ukendt (nogle titler i Mikkels katalog) og vises ikke.
    private static func subtitle(for title: Title) -> String {
        let genres = title.genres.prefix(3).joined(separator: ", ")
        guard title.year > 0 else { return genres }
        return "\(String(title.year)) · \(genres)"
    }
}

/// Hvor filmen kan ses. Brugerens egne tjenester vises først:
/// "✓ Netflix · in your subscription", ellers "Netflix · not in your services".
/// Leje og køb kaldes aldrig "in your subscription".
private struct WhereToWatch: View {
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

#Preview("Med anbefalinger") {
    NavigationStack {
        RecommendationsView(viewModel: RecommendationsViewModel(
            recommendationService: MockRecommendationService(stored: MockRecommendationService.sampleRecommendations),
            movieDataService: MockMovieDataService()
        ))
    }
}

#Preview("Tom") {
    NavigationStack {
        RecommendationsView(viewModel: RecommendationsViewModel(
            recommendationService: MockRecommendationService(delay: .seconds(2)),
            movieDataService: MockMovieDataService()
        ))
    }
}
