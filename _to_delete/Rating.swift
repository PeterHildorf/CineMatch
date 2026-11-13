//
//  Rating.swift
//  CineMatch
//

/// Brugerens bedømmelse af én film – modellens input.
/// Svarer til en række i Supabase-tabellen `ratings`.
struct Rating: Codable, Hashable, Sendable {
    /// MovieLens `movieId`.
    let movieID: Int
    /// Stjerner på MovieLens' skala 0.5–5.0. Appen bruger hele stjerner (1–5) indtil videre.
    let stars: Double
}
