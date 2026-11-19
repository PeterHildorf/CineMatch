//
//  MockRecommendationEventLogger.swift
//  CineMatch
//

import Foundation

/// Gemmer events i hukommelsen. Bruges i tests, previews og når Supabase ikke er sat op.
final class MockRecommendationEventLogger: RecommendationEventLogger {
    /// Ældste først.
    private(set) var events: [RecommendationEvent] = []

    // nonisolated: så den kan bruges som standardværdi i andre init (de køres uden for main actor).
    nonisolated init() {}

    func log(_ event: RecommendationEvent) {
        events.append(event)
    }

    // MARK: - Hjælpere til tests

    var batches: [RecommendationBatch] {
        var result: [RecommendationBatch] = []
        for case .batch(let batch) in events { result.append(batch) }
        return result
    }

    /// Alle visninger med deres batch, i rækkefølge.
    var impressions: [(batchID: UUID, impression: RecommendationImpression)] {
        var result: [(batchID: UUID, impression: RecommendationImpression)] = []
        for case let .impressions(batchID, shown) in events {
            result += shown.map { (batchID: batchID, impression: $0) }
        }
        return result
    }

    var feedback: [(batchID: UUID, movieID: Int, verdict: Verdict)] {
        var result: [(batchID: UUID, movieID: Int, verdict: Verdict)] = []
        for case let .feedback(batchID, movieID, verdict) in events {
            result.append((batchID: batchID, movieID: movieID, verdict: verdict))
        }
        return result
    }
}
