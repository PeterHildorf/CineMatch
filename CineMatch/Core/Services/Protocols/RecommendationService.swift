//
//  RecommendationService.swift
//  CineMatch
//

/// Fejl, som resten af appen forstår – uanset om anbefalingerne laves lokalt eller af en server.
enum RecommendationServiceError: Error, Equatable {
    case tooFewLikes        // brugeren har liket for få film
    case tooFewRatings      // brugeren har givet stjerner til for få film (Mikkels model)
    case notReady           // modellen kunne ikke indlæses
    case unauthorized       // sessionen er udløbet
    case network            // ingen forbindelse / timeout
    case unknown
}

/// Giver brugerens top 5. Laves i dag lokalt af `OnDeviceRecommendationService`.
protocol RecommendationService: Sendable {
    /// "Get recommendations": beregner nye anbefalinger ud fra brugerens likes.
    func requestRecompute() async throws
    /// Brugerens seneste anbefalinger, sorteret efter `rank`. Tom liste = ingen endnu.
    func latestRecommendations() async throws -> [Recommendation]
    /// Hvilken model og hvilket input de seneste anbefalinger kom fra. `nil` = ingen endnu.
    /// Bruges til at måle præcisionen pr. modelversion.
    func latestBatch() async -> RecommendationBatch?
    /// Glemmer de seneste anbefalinger ("Start fresh" i Profile). Bagefter er `latestRecommendations()` tom.
    func clearRecommendations() async
}
