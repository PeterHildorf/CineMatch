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

    var id: Int { rank }
}
