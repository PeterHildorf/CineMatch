//
//  OnDeviceMovieDataService.swift
//  CineMatch
//

/// Film fra modelfilen. Bruger modellens egne film-id'er, så likes og anbefalinger altid passer sammen.
struct OnDeviceMovieDataService: MovieDataService {
    let store: ModelStore

    /// Filmene, brugeren swiper igennem: kendte, godt bedømte film fordelt på genrer.
    func allTitles() async throws -> [Title] {
        try await recommender().onboardingFilms().map(Title.init)
    }

    /// Slår alle film i modellen op, ikke kun startfilmene.
    func titles(withIDs ids: [Int]) async throws -> [Title] {
        let recommender = try await recommender()
        return ids.compactMap(recommender.film(id:)).map(Title.init)
    }

    func search(_ query: String) async throws -> [Title] {
        try await recommender().search(query).map(Title.init)
    }

    private func recommender() async throws -> OnDeviceRecommender {
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
    init(_ film: ModelFile.Film) {
        self.init(
            id: film.id,
            tmdbId: film.tmdbId,
            title: film.title,
            year: film.year,
            genres: film.genres,
            director: film.director.isEmpty ? nil : film.director,
            cast: film.cast.isEmpty ? nil : film.cast,
            overview: film.description.isEmpty ? nil : film.description,
            runtimeMinutes: film.runtime,
            moods: film.moods,
            ageRating: film.ageRating,
            tags: film.tags
        )
    }
}
