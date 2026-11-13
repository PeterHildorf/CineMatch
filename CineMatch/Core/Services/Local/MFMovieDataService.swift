//
//  MFMovieDataService.swift
//  CineMatch
//

/// Film fra Mikkels modelfil. Film-id er TMDB-id.
///
/// Onboarding bruger de 40 varierede, kendte film fra `movielens_titles.json` (de har TMDB-id),
/// fordi Mikkels fil ikke har en liste over startfilm.
struct MFMovieDataService: MovieDataService {
    let store: MFModelStore
    /// Hvor startfilmene kommer fra.
    var starters: any MovieDataService = LocalJSONMovieDataService()

    func allTitles() async throws -> [Title] {
        let recommender = try await recommender()
        return try await starters.allTitles()
            .compactMap(\.tmdbId)
            .compactMap(recommender.movie(tmdbId:))
            .map(Title.init)
    }

    /// Slår alle film i modellen op, ikke kun startfilmene.
    func titles(withIDs ids: [Int]) async throws -> [Title] {
        let recommender = try await recommender()
        return ids.compactMap(recommender.movie(tmdbId:)).map(Title.init)
    }

    private func recommender() async throws -> MatrixFactorizationRecommender {
        do {
            return try await store.recommender()
        } catch ModelStoreError.fileNotFound {
            throw MovieDataServiceError.fileNotFound
        } catch {
            throw MovieDataServiceError.invalidData
        }
    }
}

extension Title {
    /// `year` er 0, hvis MovieLens-titlen ikke har et år.
    init(_ movie: MFModelFile.Movie) {
        let parsed = MFTitleParser.parse(movie.title)
        self.init(
            id: movie.tmdbId,
            tmdbId: movie.tmdbId,
            title: parsed.title,
            year: parsed.year ?? 0,
            genres: movie.genres
        )
    }
}
