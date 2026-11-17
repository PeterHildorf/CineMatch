//
//  RecommendationEvent.swift
//  CineMatch
//

import Foundation

// `nonisolated`, så typerne kan sendes til Supabase-klienten uden for main actor.

/// Hvilken af appens tre anbefalingsrækker det handler om. Svarer til kolonnen `pipeline` i Supabase.
nonisolated enum PipelineID: String, Codable, Sendable {
    /// Stjerner → Mikkels model.
    case stars
    /// Swipe-likes → Antons model.
    case swipe
    /// Søge-likes → Antons model, egen like-bunke.
    case search
}

/// Ét resultat fra modellen ("Get recommendations"). Alle visninger og "Seen it" hører til et batch,
/// så præcisionen kan måles pr. modelversion og ikke blandes sammen før og efter, at feedback er lært.
nonisolated struct RecommendationBatch: Hashable, Sendable {
    let id: UUID
    /// `modelVersion` fra modelfilen, fx "2026-11-17".
    let modelVersion: String
    /// Antal likes eller stjerner, modellen fik som input.
    let inputCount: Int
    let createdAt: Date

    init(id: UUID = UUID(), modelVersion: String, inputCount: Int, createdAt: Date = .now) {
        self.id = id
        self.modelVersion = modelVersion
        self.inputCount = inputCount
        self.createdAt = createdAt
    }
}

/// Én film, der blev vist i en anbefalingsliste.
nonisolated struct RecommendationImpression: Hashable, Sendable {
    let movieID: Int
    /// Modellens placering (1 = bedst). Over 10 = erstatning efter "Seen it".
    let rank: Int
    let score: Double?
    /// Pladsen på skærmen (1–10).
    let shownPosition: Int
}

/// Brugerens svar på "Seen it".
nonisolated enum RecommendationOutcome: String, Codable, Sendable {
    case seenLiked = "seen_liked"
    case seenDisliked = "seen_disliked"
}

/// Det, der logges for at måle modellernes præcision. Rækkefølgen betyder noget:
/// et batch skal logges før dets visninger og feedback.
nonisolated enum RecommendationEvent: Hashable, Sendable {
    case batch(RecommendationBatch)
    case impressions(batchID: UUID, [RecommendationImpression])
    case feedback(batchID: UUID, movieID: Int, outcome: RecommendationOutcome)
}
