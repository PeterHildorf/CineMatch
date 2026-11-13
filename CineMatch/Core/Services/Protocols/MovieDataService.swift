//
//  MovieDataService.swift
//  CineMatch
//

enum MovieDataServiceError: Error, Equatable {
    case fileNotFound
    case invalidData
}

/// Giver appen de film, brugeren kan bedømme.
/// I dag kommer de fra en lokal JSON-fil – senere måske fra Supabase eller TMDB.
protocol MovieDataService: Sendable {
    func allTitles() async throws -> [Title]
    /// Slår film op ud fra MovieLens-id'er, fx dem ML-servicen anbefaler.
    /// Ukendte id'er springes over.
    func titles(withIDs ids: [Int]) async throws -> [Title]
}

extension MovieDataService {
    // Standard-implementering: alle services får den gratis (ligesom en default-metode i et Java-interface).
    func titles(withIDs ids: [Int]) async throws -> [Title] {
        let byID = Dictionary(uniqueKeysWithValues: try await allTitles().map { ($0.id, $0) })
        // compactMap bevarer rækkefølgen fra `ids` og dropper dem, vi ikke kender.
        return ids.compactMap { byID[$0] }
    }
}
