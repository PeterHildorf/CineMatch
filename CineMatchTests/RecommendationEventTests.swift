//
//  RecommendationEventTests.swift
//  CineMatchTests
//

import Foundation
import Testing
@testable import CineMatch

/// Målinger: batches, visninger og "Seen it" logges, så præcisionen kan regnes ud i Supabase.
@MainActor
struct RecommendationEventLoggingTests {

    /// 12 kandidater (film 101–112), så der er 2 i reserve bag de 10 viste.
    private static let twelve = (1...12).map { Recommendation(rank: $0, movieID: 100 + $0, score: 1 - Double($0) / 100, reason: nil) }

    private func makeViewModel(
        _ service: MockRecommendationService = MockRecommendationService(stored: twelve),
        logger: MockRecommendationEventLogger,
        signals: MockTasteSignalService = MockTasteSignalService()
    ) -> RecommendationsViewModel {
        RecommendationsViewModel(
            recommendationService: service,
            movieDataService: MockMovieDataService(),
            signalService: signals,
            eventLogger: logger
        )
    }

    private func item(_ viewModel: RecommendationsViewModel, movieID: Int) -> RecommendationsViewModel.Item? {
        guard case .loaded(let items) = viewModel.state else { return nil }
        return items.first { $0.recommendation.movieID == movieID }
    }

    @Test func loadLogsBatchBeforeItsImpressions() async throws {
        let logger = MockRecommendationEventLogger()
        let viewModel = makeViewModel(logger: logger)

        await viewModel.load()

        let batch = try #require(logger.batches.first)
        #expect(logger.batches.count == 1)
        guard case .batch = logger.events.first else {
            Issue.record("Batchet skal logges først, fik \(logger.events)")
            return
        }
        #expect(logger.impressions.map(\.batchID) == Array(repeating: batch.id, count: 10))
        #expect(logger.impressions.map(\.impression.movieID) == Array(101...110))
        #expect(logger.impressions.map(\.impression.shownPosition) == Array(1...10))
        #expect(logger.impressions[0].impression.score == 0.99)
    }

    @Test func reloadingDoesNotLogTheSameImpressionsAgain() async {
        let logger = MockRecommendationEventLogger()
        let viewModel = makeViewModel(logger: logger)

        await viewModel.load()
        await viewModel.load()   // pull-to-refresh

        #expect(logger.batches.count == 1)
        #expect(logger.impressions.count == 10)
    }

    @Test func seenItLogsFeedbackAndTheReplacement() async throws {
        let logger = MockRecommendationEventLogger()
        let viewModel = makeViewModel(logger: logger)
        await viewModel.load()
        let batchID = try #require(logger.batches.first?.id)

        await viewModel.markSeen(try #require(item(viewModel, movieID: 104)), verdict: .bad)

        #expect(logger.feedback.count == 1)
        #expect(logger.feedback.first?.batchID == batchID)
        #expect(logger.feedback.first?.movieID == 104)
        #expect(logger.feedback.first?.verdict == .bad)
        // Film 111 rykker op som nr. 10 på skærmen, men har stadig modellens rank 11.
        let replacement = try #require(logger.impressions.last?.impression)
        #expect(replacement == RecommendationImpression(movieID: 111, rank: 11, score: 0.89, shownPosition: 10))
    }

    @Test func failedSaveLogsNoFeedback() async throws {
        let logger = MockRecommendationEventLogger()
        let viewModel = makeViewModel(logger: logger, signals: MockTasteSignalService(errorToThrow: .network))
        await viewModel.load()

        await viewModel.markSeen(try #require(item(viewModel, movieID: 101)), verdict: .great)

        #expect(logger.feedback.isEmpty)
    }

    @Test func recomputeStartsANewBatch() async throws {
        let logger = MockRecommendationEventLogger()
        let viewModel = makeViewModel(logger: logger)
        await viewModel.load()

        await viewModel.recompute()

        #expect(logger.batches.count == 2)
        let newBatchID = try #require(logger.batches.last?.id)
        let newImpressions = logger.impressions.filter { $0.batchID == newBatchID }
        #expect(newImpressions.count == MockRecommendationService.sampleRecommendations.count)
    }

    @Test func noRecommendationsLogsNothing() async {
        let logger = MockRecommendationEventLogger()
        let viewModel = makeViewModel(MockRecommendationService(), logger: logger)

        await viewModel.load()

        #expect(logger.events.isEmpty)
    }
}

/// Rækkerne, der sendes til Supabase.
struct SupabaseRowTests {

    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func rowSendsRatingEvenWhenNull() throws {
        let row = SupabaseTasteSignalService.Row(
            userID: UUID(), pipeline: "swipe", movieID: 42, signal: "like", rating: nil, source: "feedback"
        )

        let object = try json(row)

        #expect(object.keys.contains("rating"))
        #expect(object["rating"] is NSNull)
        #expect(object["movie_id"] as? Int == 42)
        #expect(object["source"] as? String == "feedback")
    }

    @Test(arguments: Verdict.allCases) @MainActor
    func rowFromSupabaseBecomesVerdict(verdict: Verdict) throws {
        let data = Data(#"{"movie_id": 7, "signal": "x", "rating": \#(verdict.score), "source": "feedback"}"#.utf8)
        let row = try JSONDecoder().decode(SupabaseTasteSignalService.Row.self, from: data)

        #expect(SupabaseTasteSignalService.signal(from: row) == TasteSignal(movieID: 7, verdict: verdict, source: .feedback))
    }

    @Test @MainActor func oldRowsAreTranslated() throws {
        func signal(_ json: String) throws -> TasteSignal? {
            let row = try JSONDecoder().decode(SupabaseTasteSignalService.Row.self, from: Data(json.utf8))
            return SupabaseTasteSignalService.signal(from: row)
        }
        // Swipe før 0005: kun like/dislike.
        #expect(try signal(#"{"movie_id": 1, "signal": "like", "rating": null, "source": "onboarding"}"#)?.verdict == .great)
        #expect(try signal(#"{"movie_id": 1, "signal": "dislike", "rating": null, "source": "onboarding"}"#)?.verdict == .bad)
        // Before 0006, Great used 3 + like; Neutral must remain neutral.
        #expect(try signal(#"{"movie_id": 1, "signal": "like", "rating": 3, "source": "onboarding"}"#)?.verdict == .great)
        #expect(try signal(#"{"movie_id": 1, "signal": "neutral", "rating": 3, "source": "onboarding"}"#)?.verdict == .neutral)
        // Gamle halve stjerner.
        #expect(try signal(#"{"movie_id": 1, "signal": "like", "rating": 4.5, "source": "onboarding"}"#)?.verdict == .fantastic)
        #expect(try signal(#"{"movie_id": 1, "signal": "neutral", "rating": 2.5, "source": "onboarding"}"#)?.verdict == .neutral)
        #expect(try signal(#"{"movie_id": 1, "signal": "dislike", "rating": 1.5, "source": "onboarding"}"#)?.verdict == .bad)
    }

    @Test func feedbackRowSendsScoreAndOutcome() throws {
        let object = try json(SupabaseRecommendationEventLogger.FeedbackRow(batchID: UUID(), movieID: 3, verdict: .fantastic))

        #expect(object["score"] as? Int == 5)
        #expect(object["outcome"] as? String == "seen_liked")
    }

    @Test @MainActor func unknownSignalIsSkipped() throws {
        let data = Data(#"{"movie_id": 7, "signal": "superlike", "rating": null, "source": "onboarding"}"#.utf8)
        let row = try JSONDecoder().decode(SupabaseTasteSignalService.Row.self, from: data)

        #expect(SupabaseTasteSignalService.signal(from: row) == nil)
    }

    @Test func impressionSendsScoreAsNull() throws {
        let row = SupabaseRecommendationEventLogger.ImpressionRow(batchID: UUID(), movieID: 1, rank: 1, score: nil, shownPosition: 1)

        let object = try json(row)

        #expect(object["score"] is NSNull)
        #expect(object["shown_position"] as? Int == 1)
    }
}
