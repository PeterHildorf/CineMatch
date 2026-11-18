//
//  MockMovieDataService.swift
//  CineMatch
//

import Foundation

/// Falsk filmliste til previews og tests. Bruger rigtige MovieLens-id'er.
/// Rige demo-film med instruktør, handling og TMDB-id ligger i `DemoData`.
struct MockMovieDataService: MovieDataService {
    static let sampleTitles: [Title] = [
        Title(id: 318, tmdbId: 278, title: "The Shawshank Redemption", year: 1994, genres: ["Crime", "Drama"]),
        Title(id: 2571, tmdbId: 603, title: "The Matrix", year: 1999, genres: ["Action", "Sci-Fi", "Thriller"]),
        Title(id: 1, tmdbId: 862, title: "Toy Story", year: 1995, genres: ["Adventure", "Animation", "Children", "Comedy", "Fantasy"]),
        Title(id: 1265, tmdbId: 137, title: "Groundhog Day", year: 1993, genres: ["Comedy", "Fantasy", "Romance"]),
        Title(id: 1258, tmdbId: 694, title: "The Shining", year: 1980, genres: ["Horror"]),
    ]

    /// Filmene i Swipe (`allTitles`).
    var titles: [Title] = sampleTitles
    /// Hele kataloget til opslag og søgning. `nil` = det samme som `titles`.
    /// Så kan demoen anbefale film, der ikke er i Swipe-bunken.
    var catalog: [Title]? = nil
    /// Sæt en fejl i tests for at simulere, at filmlisten ikke kan indlæses.
    var errorToThrow: MovieDataServiceError?

    func allTitles() async throws -> [Title] {
        if let errorToThrow { throw errorToThrow }
        return titles
    }

    func titles(withIDs ids: [Int]) async throws -> [Title] {
        if let errorToThrow { throw errorToThrow }
        let byID = Dictionary((catalog ?? titles).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    func search(_ query: String) async throws -> [Title] {
        if let errorToThrow { throw errorToThrow }
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return [] }
        return (catalog ?? titles).filter { title in
            [title.title, title.director ?? "", title.cast ?? ""].contains { $0.lowercased().contains(key) }
        }
    }
}
