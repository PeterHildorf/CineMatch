//
//  MovieDataService.swift
//  CineMatch
//

import Foundation
enum MovieDataServiceError: Error, Equatable {
    case fileNotFound
    case invalidData
}

/// Giver appen de film, brugeren kan bedømme.
/// I dag kommer de fra en lokal JSON-fil – senere måske fra Supabase eller TMDB.
protocol MovieDataService: Sendable {
    func allTitles() async throws -> [Title]
    /// Looks up app-facing IDs (TMDB IDs in the active catalogue), preserving requested order.
    /// Ukendte id'er springes over.
    func titles(withIDs ids: [Int]) async throws -> [Title]
    /// Søger film frem på titel. Tom forespørgsel giver ingen resultater.
    /// On-device-servicen søger i hele modellens katalog; mocks søger i deres egen liste.
    func search(_ query: String) async throws -> [Title]
}

extension MovieDataService {
    // Standard-implementering: alle services får den gratis (ligesom en default-metode i et Java-interface).
    func titles(withIDs ids: [Int]) async throws -> [Title] {
        let byID = Dictionary(uniqueKeysWithValues: try await allTitles().map { ($0.id, $0) })
        // compactMap bevarer rækkefølgen fra `ids` og dropper dem, vi ikke kender.
        return ids.compactMap { byID[$0] }
    }

    /// Simpel søgning for services uden deres egen (mocks, lokal JSON): filtrér titler på delstreng.
    /// `OnDeviceMovieDataService` overskriver den med modellens hurtige indeks-søgning.
    func search(_ query: String) async throws -> [Title] {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return [] }
        return try await allTitles().filter { $0.title.lowercased().contains(key) }
    }
}
