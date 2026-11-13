//
//  RateMoviesView.swift
//  CineMatch
//

import SwiftUI

/// Listen hvor brugeren giver film 1–5 stjerner.
struct RateMoviesView: View {
    let viewModel: RateMoviesViewModel

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView("Henter film …")
            case .failed(let message):
                ContentUnavailableView {
                    Label("Ingen film", systemImage: "film")
                } description: {
                    Text(message)
                } actions: {
                    Button("Prøv igen") { Task { await viewModel.load() } }
                }
            case .loaded:
                titleList
            }
        }
        .navigationTitle("Bedøm film")
        .task { await viewModel.load() }
    }

    private var titleList: some View {
        List {
            Section {
                ForEach(viewModel.titles) { title in
                    TitleRatingRow(title: title, stars: viewModel.stars(for: title)) { stars in
                        Task { await viewModel.setStars(stars, for: title) }
                    }
                }
            } header: {
                progressHeader
            }
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            if viewModel.hasEnoughRatings {
                Label("\(viewModel.ratedCount) film bedømt – du kan få anbefalinger", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("Bedøm mindst \(RateMoviesViewModel.minimumRatings) film (\(viewModel.ratedCount)/\(RateMoviesViewModel.minimumRatings))")
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
        .font(.footnote)
        .textCase(nil)   // List-headers er ellers med STORE BOGSTAVER
    }
}

/// Én film i listen: titel, år, genrer og stjerner.
private struct TitleRatingRow: View {
    let title: Title
    let stars: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.title)
                .font(.headline)
            Text("\(String(title.year)) · \(title.genres.prefix(3).joined(separator: ", "))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            StarRatingView(stars: stars, onSelect: onSelect)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        RateMoviesView(viewModel: RateMoviesViewModel(
            movieDataService: MockMovieDataService(),
            ratingService: MockRatingService(ratings: [Rating(movieID: 2571, stars: 5)])
        ))
    }
}
