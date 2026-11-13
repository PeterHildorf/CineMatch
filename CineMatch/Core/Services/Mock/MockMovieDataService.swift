//
//  MockMovieDataService.swift
//  CineMatch
//

/// Falsk filmliste til previews og tests. Bruger rigtige MovieLens-id'er.
struct MockMovieDataService: MovieDataService {
    static let sampleTitles: [Title] = [
        Title(id: 318, tmdbId: 278, title: "The Shawshank Redemption", year: 1994, genres: ["Crime", "Drama"]),
        Title(id: 2571, tmdbId: 603, title: "The Matrix", year: 1999, genres: ["Action", "Sci-Fi", "Thriller"]),
        Title(id: 1, tmdbId: 862, title: "Toy Story", year: 1995, genres: ["Adventure", "Animation", "Children", "Comedy", "Fantasy"]),
        Title(id: 1265, tmdbId: 137, title: "Groundhog Day", year: 1993, genres: ["Comedy", "Fantasy", "Romance"]),
        Title(id: 1258, tmdbId: 694, title: "The Shining", year: 1980, genres: ["Horror"]),
    ]

    var titles: [Title] = sampleTitles
    /// Sæt en fejl i tests for at simulere, at filmlisten ikke kan indlæses.
    var errorToThrow: MovieDataServiceError?

    func allTitles() async throws -> [Title] {
        if let errorToThrow { throw errorToThrow }
        return titles
    }
}
