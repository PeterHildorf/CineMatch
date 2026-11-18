//
//  TasteSignal.swift
//  CineMatch
//

/// Brugerens dom over én film – modellernes input.
/// Svarer til en række i Supabase-tabellen `taste_signals`.
///
/// Alle bedømmelser bruger samme skala (`Verdict`): Haven't seen 0 · Horrible 1 · Bad 2 · Great 3 · Fantastic 5.
/// "Haven't seen" gemmes også, så filmen ikke vises i Swipe igen. Den er IKKE modelinput og
/// udelukker ikke filmen fra anbefalingerne (brugeren har jo ikke set den).
struct TasteSignal: Codable, Hashable, Sendable {
    /// Grov opdeling til Antons nuværende model (som kun tager likes) og kolonnen `signal` i Supabase.
    enum Kind: String, Codable, Sendable {
        case like
        case dislike
        /// "Haven't seen".
        case unseen
    }

    /// Hvor svaret kom fra. Svarer til kolonnen `source` i `taste_signals`.
    enum Source: String, Codable, Sendable {
        /// Swipe eller søgning.
        case onboarding
        /// "Seen it" på en anbefaling. Bruges både som modellens input og til at måle præcisionen.
        case feedback
    }

    /// Film-id fra den model, appen bruger (TMDB-id med Mikkels model, Letterboxd-id med Antons).
    let movieID: Int
    let verdict: Verdict
    var source: Source = .onboarding

    /// Tallet, modellerne får (0, 1, 2, 3 eller 5).
    var score: Int { verdict.score }

    var kind: Kind {
        switch verdict {
        case .notSeen: .unseen
        case .horrible, .bad: .dislike
        case .great, .fantastic: .like
        }
    }
}

extension Array where Element == TasteSignal {
    /// Film, brugeren har set og bedømt (alt undtagen "Haven't seen"). De må aldrig anbefales.
    var seenMovieIDs: Set<Int> { Set(filter(\.verdict.isSeen).map(\.movieID)) }

    /// Film, brugeren kan lide (Great/Fantastic) – Fantastic først, ellers nyeste først.
    /// Antons model bruger de første `maxLiked`, så de stærkeste likes skal forrest.
    var likedMovieIDs: [Int] {
        enumerated()
            .filter { $0.element.verdict.isPositive }
            .sorted { ($0.element.score, -$0.offset) > ($1.element.score, -$1.offset) }
            .map(\.element.movieID)
    }
}
