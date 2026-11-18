//
//  SearchView.swift
//  CineMatch
//

import SwiftUI

/// Søg efter film i Antons on-device-katalog og bedømm dem, du har set (samme skala som Swipe).
/// Du kan søge på titel, instruktør eller skuespiller – eller browse på genre, hvis du er i tvivl.
/// Dommene lander i samme bunke som Swipe, så Today ændrer sig med det samme.
struct SearchView: View {
    @Bindable var viewModel: SearchViewModel

    var body: some View {
        content
            .navigationTitle("Search")
            .searchable(text: $viewModel.query, prompt: "Title, director or actor")
            // Kører søgningen, hver gang teksten ændrer sig. `task(id:)` afbryder den forrige søgning.
            .task(id: viewModel.query) { await viewModel.runSearch() }
            .task {
                await viewModel.loadVerdicts()
                await viewModel.loadSuggestions()
            }
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
            resultsList
        }
    }

    // MARK: - Browse (tomt søgefelt)

    @ViewBuilder
    private var browse: some View {
        if viewModel.suggestions.isEmpty {
            ContentUnavailableView {
                Label("Find movies you love", systemImage: "magnifyingglass")
            } description: {
                Text("Search by title, director or actor, then rate the movies you've seen.")
            }
        } else {
            VStack(spacing: 0) {
                genreChips
                List {
                    Section {
                        ForEach(viewModel.browseResults) { title in row(for: title) }
                    } header: {
                        Text("Popular to get started · rate the ones you've seen")
                            .textCase(nil)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var genreChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", isSelected: viewModel.selectedGenre == nil) {
                    viewModel.selectedGenre = nil
                }
                ForEach(viewModel.genres, id: \.self) { genre in
                    chip(title: genre, isSelected: viewModel.selectedGenre == genre) {
                        viewModel.selectedGenre = viewModel.selectedGenre == genre ? nil : genre
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Søgeresultater

    private var resultsList: some View {
        List {
            if viewModel.ratedCount > 0 {
                Section {
                    Text("^[\(viewModel.ratedCount) movie](inflect: true) rated")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if let errorMessage = viewModel.errorMessage {
                Section {
                    InlineError(message: errorMessage)
                }
            }
            Section {
                ForEach(viewModel.results) { title in row(for: title) }
            }
        }
        .listStyle(.plain)
    }

    private func row(for title: Title) -> some View {
        SearchRow(
            title: title,
            posterURL: viewModel.posterURLs[title.id],
            verdict: viewModel.verdict(for: title),
            onRate: { verdict in Task { await viewModel.rate(title, verdict) } },
            onRemove: { Task { await viewModel.removeRating(title) } }
        )
        .task { await viewModel.loadPoster(for: title) }
    }
}

/// Én film: plakat, titel, år/genre, instruktør/skuespillere og "Rate"-menuen.
private struct SearchRow: View {
    let title: Title
    let posterURL: URL?
    let verdict: Verdict?
    let onRate: (Verdict) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PosterImage(url: posterURL)
                .frame(width: 50, height: 75)
                .clipShape(.rect(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(title.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let credits {
                    Text(credits)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VerdictMenu(current: verdict, title: "Rate", onRemove: onRemove, onRate: onRate)
                .accessibilityLabel(verdict.map { "\(title.title): \($0.label)" } ?? "Rate \(title.title)")
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let genres = title.genres.prefix(3).joined(separator: ", ")
        return title.year > 0 ? "\(String(title.year)) · \(genres)" : genres
    }

    /// "Noah Baumbach · Adam Driver, Greta Gerwig" – så man kan genkende filmen uden titlen.
    private var credits: String? {
        var parts: [String] = []
        if let director = title.director, !director.isEmpty { parts.append(director) }
        if let cast = title.cast, !cast.isEmpty {
            parts.append(cast.split(separator: ",").prefix(2).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ", "))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        SearchView(viewModel: SearchViewModel(
            movieDataService: MockMovieDataService(titles: DemoData.titles),
            signalService: MockTasteSignalService(signals: [TasteSignal(movieID: 807, verdict: .fantastic)]),
            mediaService: MockTitleMediaService.demo
        ))
    }
}
