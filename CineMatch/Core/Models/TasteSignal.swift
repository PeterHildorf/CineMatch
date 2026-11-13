//
//  TasteSignal.swift
//  CineMatch
//

/// Brugerens mening om én film – modellens input.
/// Svarer til en række i Supabase-tabellen `taste_signals`.
///
/// To måder at svare på (begge gemmes rå):
/// - swipe/knap: like eller dislike, ingen stjerner
/// - stjerner: ½–5 i halve trin. `kind` udledes af stjernerne, så Antons model også kan bruge dem.
struct TasteSignal: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case like
        case dislike
        /// Kun ved stjerner midt på skalaen (2½–3). Hverken like eller dislike.
        case neutral
    }

    /// Film-id fra den model, appen bruger (TMDB-id med Mikkels model, Letterboxd-id med Antons).
    let movieID: Int
    let kind: Kind
    /// Stjerner ½–5, hvis brugeren gav stjerner. `nil` ved swipe.
    var rating: Double? = nil

    /// Stjerner → like/dislike: 3½ eller mere er like, 2 eller mindre er dislike.
    static func kind(forStars stars: Double) -> Kind {
        if stars >= 3.5 { return .like }
        if stars <= 2.0 { return .dislike }
        return .neutral
    }
}
