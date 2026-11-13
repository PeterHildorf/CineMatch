//
//  RatingViewModel.swift
//  CineMatch
//

import Foundation
import Observation

/// "Rate movies": en liste, hvor brugeren giver ½–5 stjerner i vilkårlig rækkefølge.
/// Input til Mikkels model. Tryk på samme antal stjerner igen fjerner ratingen.
@Observable
@MainActor
final class RatingViewModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var titles: [Title] = []
    /// Stjerner pr. film-id (TMDB-id).
    private(set) var ratings: [Int: Double] = [:]
    /// Plakater pr. film-id. Hentes, når rækken vises.
    private(set) var posterURLs: [Int: URL] = [:]
    /// Vises kort, hvis en rating ikke kunne gemmes.
    var errorMessage: String?

    private let movieDataService: any MovieDataService
    private let signalService: any TasteSignalService
    private let mediaService: any TitleMediaService

    init(
        movieDataService: any MovieDataService,
        signalService: any TasteSignalService,
        mediaService: any TitleMediaService = MockTitleMediaService()
    ) {
        self.movieDataService = movieDataService
        self.signalService = signalService
        self.mediaService = mediaService
    }

    var ratedCount: Int { ratings.count }
    var hasEnoughRatings: Bool { ratedCount >= TasteInput.minimumCount }
    var progressText: String {
        if hasEnoughRatings { return "\(ratedCount) rated · rate more for better recommendations" }
        let missing = TasteInput.minimumCount - ratedCount
        return "Rate \(missing) more \(missing == 1 ? "movie" : "movies") with stars"
    }

    func rating(for title: Title) -> Double {
        ratings[title.id] ?? 0
    }

    // MARK: - Indlæsning

    func load() async {
        state = .loading
        do {
            async let loadedTitles = movieDataService.allTitles()
            async let loadedSignals = signalService.allSignals()
            titles = try await loadedTitles
            ratings = Dictionary(
                try await loadedSignals.compactMap { signal in signal.rating.map { (signal.movieID, $0) } },
                uniquingKeysWith: { newest, _ in newest }
            )
            state = .loaded
        } catch {
            state = .failed("Couldn't load movies. Please try again.")
        }
    }

    func loadPoster(for title: Title) async {
        guard posterURLs[title.id] == nil,
              let url = await mediaService.media(for: title)?.posterURL else { return }
        posterURLs[title.id] = url
    }

    // MARK: - Rating

    /// Giver ½–5 stjerner. Samme antal igen fjerner ratingen.
    func rate(_ title: Title, stars: Double) async {
        let stars = min(max((stars * 2).rounded() / 2, 0.5), 5)
        let previous = ratings[title.id]
        errorMessage = nil

        // Opdatér skærmen med det samme ("optimistisk"), og ret tilbage, hvis det ikke kan gemmes.
        if previous == stars {
            ratings[title.id] = nil
            do {
                try await signalService.deleteSignal(movieID: title.id)
            } catch {
                ratings[title.id] = previous
                errorMessage = "Couldn't remove your rating of \(title.title). Please try again."
            }
            return
        }

        ratings[title.id] = stars
        do {
            try await signalService.save(TasteSignal(movieID: title.id, kind: TasteSignal.kind(forStars: stars), rating: stars))
        } catch {
            ratings[title.id] = previous
            errorMessage = "Couldn't save your rating of \(title.title). Please try again."
        }
    }
}
