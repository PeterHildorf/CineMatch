import Foundation

/// One supported TMDB catalogue for Swipe, onboarding, Search and recommendation lookup.
struct ConditionalNeighborMovieDataService: MovieDataService {
    let store: ConditionalNeighborModelStore

    func allTitles() async throws -> [Title] {
        let model = try await recommender()
        // Familiar films appear first, without excluding the rest of the supported catalogue.
        return model.eligibleMovies.sorted {
            $0.trainingCount != $1.trainingCount
                ? $0.trainingCount > $1.trainingCount
                : $0.movieLensId < $1.movieLensId
        }.compactMap(Title.init(conditionalMovie:))
    }

    func titles(withIDs ids: [Int]) async throws -> [Title] {
        let model = try await recommender()
        return ids.compactMap(model.movie(tmdbId:)).compactMap(Title.init(conditionalMovie:))
    }

    func search(_ query: String) async throws -> [Title] {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return [] }
        return try await allTitles().filter { $0.title.localizedStandardContains(key) }
    }

    private func recommender() async throws -> ConditionalNeighborRecommender {
        do { return try await store.recommender() }
        catch ModelStoreError.fileNotFound { throw MovieDataServiceError.fileNotFound }
        catch { throw MovieDataServiceError.invalidData }
    }
}

extension Title {
    init?(conditionalMovie movie: ConditionalNeighborModelFile.Movie) {
        guard movie.eligible, let tmdbID = movie.tmdbId else { return nil }
        self.init(id: tmdbID, tmdbId: tmdbID, title: movie.title, year: movie.year, genres: movie.genres)
    }
}
