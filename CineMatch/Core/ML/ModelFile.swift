//
//  ModelFile.swift
//  CineMatch
//

import Foundation

/// Indholdet af `cinematch_model.json`: Antons model eksporteret af `ml/export_for_app.py`.
///
/// Python har på forhånd regnet ud, hvilke film der ligner hinanden, og hvorfor.
/// Appen slår bare op i filen (se `OnDeviceRecommender`).
/// `nonisolated`, fordi filen læses uden for main actor (den er flere MB).
nonisolated struct ModelFile: Decodable, Sendable {
    nonisolated struct Film: Decodable, Hashable, Sendable {
        /// Letterboxd-id fra Antons datasæt. Det er film-id'et i hele appen nu.
        let id: Int
        /// TMDB-id, hvis eksporten har det. Ellers søger appen filmen frem på titel og år.
        let tmdbId: Int?
        let title: String
        let year: Int
        let genres: [String]
        let director: String
        let cast: String
        let description: String
        let runtime: Int?
        /// Letterboxd-gennemsnit (0–5).
        let rating: Double
        /// Rating som z-score. Giver et lille plus til godt bedømte film, som i Antons model.
        let quality: Double
    }

    /// Én film, der ligner en anden. Korte navne holder filen lille.
    nonisolated struct Neighbor: Decodable, Hashable, Sendable {
        /// Index i `films`.
        let i: Int
        /// Similarity 0–1 (cosinus), samme tal som Antons model giver.
        let s: Double
        /// Breakdown: `[feature-index, bidrag]`. Bidragene summer til `s`.
        let b: [[Double]]
        /// Fælles træk: `[explain-label-index, string-index, string-index, …]`.
        let x: [[Int]]
    }

    let formatVersion: Int
    let modelVersion: String
    let qualityBoost: Double
    /// Antons model bruger højst så mange likes.
    let maxLiked: Int
    /// Navne på feature-typer til breakdown, fx "Director" og "Themes".
    let featureLabels: [String]
    /// Navne på grupper af fælles træk, fx "Director", "Cast", "Themes".
    let explainLabels: [String]
    /// Fælles tekst-tabel (navne, temaer, ord), som `Neighbor.x` peger ind i.
    let strings: [String]
    /// Sorteret efter popularitet (mest kendte først).
    let films: [Film]
    /// Varierede, kendte film til onboarding-gitteret.
    let starterIDs: [Int]
    /// `neighbors[i]` er de mest lignende film for `films[i]`, bedste først.
    let neighbors: [[Neighbor]]
}
