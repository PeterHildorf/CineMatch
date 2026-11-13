//
//  RateMoviesViewModel.swift
//  CineMatch
//

import Foundation
import Observation

/// Viser filmlisten og gemmer brugerens stjerner – modellens input.
@Observable
@MainActor
final class RateMoviesViewModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// Foreslået minimum i docs/ml_contract.md (ML-servicen svarer 422 under dette).
    static let minimumRatings = 5

    private(set) var state: State = .loading
    private(set) var titles: [Title] = []
    /// Hele stjerner 1–5 pr. MovieLens-id. Mangler en film her, er den ikke bedømt.
    private(set) var starsByMovieID: [Int: Int] = [:]
    /// Vises kort, hvis en enkelt bedømmelse ikke kunne gemmes.
    var errorMessage: String?

    private let movieDataService: any MovieDataService
    private let ratingService: any RatingService

    init(movieDataService: any MovieDataService, ratingService: any RatingService) {
        self.movieDataService = movieDataService
        self.ratingService = ratingService
    }

    var ratedCount: Int { starsByMovieID.count }
    var hasEnoughRatings: Bool { ratedCount >= Self.minimumRatings }

    func stars(for title: Title) -> Int {
        starsByMovieID[title.id] ?? 0
    }

    // MARK: - Indlæsning

    func load() async {
        state = .loading
        do {
            // `async let` starter begge kald samtidig og venter på dem bagefter.
            async let loadedTitles = movieDataService.allTitles()
            async let loadedRatings = ratingService.allRatings()
            titles = try await loadedTitles
            starsByMovieID = Dictionary(
                uniqueKeysWithValues: try await loadedRatings.map { ($0.movieID, Int($0.stars.rounded())) }
            )
            state = .loaded
        } catch {
            state = .failed("Kunne ikke hente filmene. Tjek din forbindelse, og prøv igen.")
        }
    }

    // MARK: - Bedømmelse

    /// Sætter 1–5 stjerner. Trykker man på det samme antal igen, fjernes bedømmelsen.
    func setStars(_ stars: Int, for title: Title) async {
        let previous = starsByMovieID[title.id]
        let newValue: Int? = (stars == previous) ? nil : min(max(stars, 1), 5)

        // Opdatér skærmen med det samme ("optimistisk"), og ret tilbage hvis det fejler.
        starsByMovieID[title.id] = newValue
        errorMessage = nil

        do {
            if let newValue {
                try await ratingService.save(Rating(movieID: title.id, stars: Double(newValue)))
            } else {
                try await ratingService.deleteRating(movieID: title.id)
            }
        } catch {
            starsByMovieID[title.id] = previous
            errorMessage = "Kunne ikke gemme din bedømmelse af \(title.title). Prøv igen."
        }
    }
}
