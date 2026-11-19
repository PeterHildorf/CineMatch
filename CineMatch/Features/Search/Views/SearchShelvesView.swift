//
//  SearchShelvesView.swift
//  CineMatch
//

import SwiftUI

/// Search: vandrette rækker med plakater i stedet for én lang liste. Den gamle liste ligger i `SearchView`.
///
/// - Tomt søgefelt: rækker ("Popular", årtier, genrer) med film, brugeren ikke har bedømt.
/// - Søgning: plakater i et gitter.
/// - Ét tryk på en plakat åbner en menu med de fem domme (og "Remove rating", hvis den er bedømt).
/// Bruger samme `SearchViewModel` som den gamle Search, så dommene lander samme sted.
struct SearchShelvesView: View {
    @Bindable var viewModel: SearchViewModel

    /// Tæller op, hver gang brugeren bedømmer en film, så den kan vibrere.
    @State private var ratedTick = 0

    var body: some View {
        content
            .navigationTitle("Search")
            .searchable(text: $viewModel.query, prompt: "Movie title")
            .task(id: viewModel.query) { await viewModel.runSearch() }
            .task {
                await viewModel.loadVerdicts()
                await viewModel.loadSuggestions()
            }
            // Vibration, når en film er bedømt fra menuen.
            .sensoryFeedback(.success, trigger: ratedTick)
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasQuery {
            browse
        } else if viewModel.results.isEmpty {
            if viewModel.isSearching {
                ProgressView("Searching …")
            } else {
                ContentUnavailableView.search(text: viewModel.query)
            }
        } else {
            resultsGrid
        }
    }

    // MARK: - Rækker (tomt søgefelt)

    @ViewBuilder
    private var browse: some View {
        let shelves = viewModel.shelves
        if shelves.isEmpty {
            ContentUnavailableView {
                Label("Find movies you love", systemImage: "magnifyingglass")
            } description: {
                Text("Search by title, then rate the movies you've seen.")
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    header
                    ForEach(shelves) { shelf in shelfRow(shelf) }
                }
                .padding(.vertical)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headerText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let errorMessage = viewModel.errorMessage {
                InlineError(message: errorMessage)
            }
        }
        .padding(.horizontal)
    }

    private var headerText: String {
        let hint = "Tap a poster you've seen to rate it."
        guard viewModel.ratedCount > 0 else { return hint }
        return "\(viewModel.ratedCount) rated · \(hint)"
    }

    private func shelfRow(_ shelf: SearchShelf) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(shelf.title)
                .font(.title3.bold())
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(shelf.titles) { title in
                        posterCell(title)
                            .frame(width: 112)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    // MARK: - Søgeresultater

    private var resultsGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let errorMessage = viewModel.errorMessage {
                    InlineError(message: errorMessage)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3), spacing: 18) {
                    ForEach(viewModel.results) { title in posterCell(title) }
                }
            }
            .padding()
        }
    }

    // MARK: - Plakat

    private func posterCell(_ title: Title) -> some View {
        let verdict = viewModel.verdict(for: title)
        // Ét tryk åbner menuen. Bedste dom øverst, tæt på tommelfingeren.
        return Menu {
            Section(title.title) {
                ForEach(Verdict.seenOptions.reversed()) { option in
                    Button(option.label, systemImage: option.systemImage) {
                        ratedTick += 1
                        Task { await viewModel.rate(title, option) }
                    }
                }
            }
            if verdict?.isSeen == true {
                Button("Remove rating", systemImage: "xmark", role: .destructive) {
                    Task { await viewModel.removeRating(title) }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                PosterImage(url: viewModel.posterURLs[title.id])
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.primary.opacity(0.08)))
                    .overlay(alignment: .topTrailing) {
                        if let verdict, verdict.isSeen { badge(verdict) }
                    }
                Text(title.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if title.year > 0 {
                    Text(String(title.year))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(verdict.map { "\(title.title), rated \($0.label)" } ?? title.title)
        .accessibilityHint("Rate this movie")
        .task { await viewModel.loadPoster(for: title) }
    }

    private func badge(_ verdict: Verdict) -> some View {
        Image(systemName: verdict.systemImage)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(7)
            .background(verdict.tint, in: .circle)
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            .padding(6)
    }
}

#Preview {
    NavigationStack {
        SearchShelvesView(viewModel: SearchViewModel(
            movieDataService: MockMovieDataService(titles: DemoData.titles),
            signalService: MockTasteSignalService(signals: [TasteSignal(movieID: 807, verdict: .fantastic)]),
            mediaService: MockTitleMediaService.demo
        ))
    }
}
