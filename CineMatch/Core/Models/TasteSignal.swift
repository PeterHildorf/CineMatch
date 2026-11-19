//
//  TasteSignal.swift
//  CineMatch
//

import Foundation

/// Brugerens dom over én film – modellernes input.
/// Svarer til en række i Supabase-tabellen `taste_signals`.
///
/// Alle bedømmelser bruger samme skala (`Verdict`): Haven't seen 0 · Horrible 1 · Bad 2 · Neutral 3 · Great 4 · Fantastic 5.
/// "Haven't seen" gemmes også, så filmen ikke vises i Swipe igen før efter `Verdict.notSeenCooldown`.
/// Den er IKKE modelinput og udelukker ikke filmen fra anbefalingerne (brugeren har jo ikke set den).
struct TasteSignal: Codable, Hashable, Sendable {
    /// Grov opdeling til Antons nuværende model (som kun tager likes) og kolonnen `signal` i Supabase.
    enum Kind: String, Codable, Sendable {
        case like
        case neutral
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

    /// TMDB ID at the active app boundary. The compatibility adapter translates legacy Letterboxd rows.
    let movieID: Int
    let verdict: Verdict
    var source: Source = .onboarding
    /// Hvornår svaret blev givet (`updated_at` i Supabase). `nil` = ukendt, regnes som lige nu.
    var answeredAt: Date? = nil

    /// Tallet, modellerne får (0–5).
    var score: Int { verdict.score }

    var kind: Kind {
        switch verdict {
        case .notSeen: .unseen
        case .horrible, .bad: .dislike
        case .neutral: .neutral
        case .great, .fantastic: .like
        }
    }
}

extension Array where Element == TasteSignal {
    /// Film i Swipe, der ikke skal vises nu: alle sete film og film sprunget over inden for `notSeenCooldown`.
    func hiddenFromSwipe(now: Date = .now) -> Set<Int> {
        Set(filter { signal in
            guard signal.verdict == .notSeen else { return true }
            return now.timeIntervalSince(signal.answeredAt ?? now) < Verdict.notSeenCooldown
        }.map(\.movieID))
    }

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
