//
//  RatingService.swift
//  CineMatch
//

enum RatingServiceError: Error, Equatable {
    case network
    case unknown
}

/// Gemmer og henter den indloggede brugers bedømmelser.
/// Hvilken bruger det er, ved servicen selv (via sessionen) – ViewModels skal ikke sende et user-id med.
protocol RatingService: Sendable {
    func allRatings() async throws -> [Rating]
    /// Gemmer eller overskriver bedømmelsen af en film.
    func save(_ rating: Rating) async throws
    func deleteRating(movieID: Int) async throws
}
