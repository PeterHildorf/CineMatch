//
//  TasteSignalService.swift
//  CineMatch
//

enum TasteSignalServiceError: Error, Equatable {
    case network
    case unknown
}

/// Gemmer og henter den indloggede brugers likes og dislikes.
/// Hvilken bruger det er, ved servicen selv (via sessionen) – ViewModels sender ikke et user-id med.
protocol TasteSignalService: Sendable {
    /// Alle svar, nyeste først (modellen bruger de nyeste likes, hvis der er mange).
    func allSignals() async throws -> [TasteSignal]
    /// Gemmer eller overskriver brugerens svar på en film.
    func save(_ signal: TasteSignal) async throws
    func deleteSignal(movieID: Int) async throws
}
