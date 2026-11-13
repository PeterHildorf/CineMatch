//
//  RatingView.swift
//  CineMatch
//

import SwiftUI

/// Liste over film med ½–5 stjerner på hver række. Input til Mikkels model.
struct RatingView: View {
    let viewModel: RatingViewModel

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView("Loading movies …")
            case .failed(let message):
                ContentUnavailableView {
                    Label("Something went wrong", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await viewModel.load() } }
                }
            case .loaded:
                list
            }
        }
        .navigationTitle("Rate movies")
        .task {
            if viewModel.state == .loading { await viewModel.load() }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(viewModel.titles) { title in
                    RatingRow(title: title, rating: viewModel.rating(for: title), posterURL: viewModel.posterURLs[title.id]) { stars in
                        Task { await viewModel.rate(title, stars: stars) }
                    }
                    .task { await viewModel.loadPoster(for: title) }
                }
            } header: {
                header
            }
        }
        .listStyle(.plain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(
                value: Double(min(viewModel.ratedCount, TasteInput.minimumCount)),
                total: Double(TasteInput.minimumCount)
            )
            Text(viewModel.progressText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Tap the left half of a star for ½. Tap the same rating again to remove it. Skip movies you haven't seen.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .textCase(nil)
        .padding(.vertical, 6)
    }
}

/// Én film: plakat, titel, år og stjerner.
private struct RatingRow: View {
    let title: Title
    let rating: Double
    let posterURL: URL?
    let onRate: (Double) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PosterImage(url: posterURL)
                .frame(width: 50, height: 75)
                .clipShape(.rect(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 6) {
                Text(title.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                StarRatingControl(value: rating, starSize: 28, onRate: onRate)
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let genres = title.genres.prefix(3).joined(separator: ", ")
        return title.year > 0 ? "\(String(title.year)) · \(genres)" : genres
    }
}

#Preview {
    NavigationStack {
        RatingView(viewModel: RatingViewModel(
            movieDataService: MockMovieDataService(),
            signalService: MockTasteSignalService(signals: [TasteSignal(movieID: 2571, kind: .like, rating: 4.5)])
        ))
    }
}
