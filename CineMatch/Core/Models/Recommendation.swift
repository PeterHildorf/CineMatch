//
//  Recommendation.swift
//  CineMatch
//

/// Én anbefaling fra modellen.
/// Laves lokalt af `OnDeviceRecommendationService`.
struct Recommendation: Codable, Hashable, Identifiable, Sendable {
    /// Placering 1–5.
    let rank: Int
    /// Film-id. Titel, år osv. slås op via `MovieDataService`.
    let movieID: Int
    let score: Double?
    /// Færdig engelsk tekst, fx "Because you liked Se7en · Director: David Fincher".
    let reason: String?
    /// Den film, brugeren har set, som anbefalingen kommer fra ("Because you liked …").
    /// Bruges til at finde fælles instruktør, cast og temaer i TMDB. `nil` = ingen enkelt film.
    var becauseMovieID: Int? = nil

    var id: Int { rank }
}
