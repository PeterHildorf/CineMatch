import Foundation
import Testing
@testable import CineMatch

@MainActor
struct RecommendationEventIdentityTests {
    /// Holds one send in flight while later events remain queued.
    private actor Gate {
        private var entered = false
        private var entering: CheckedContinuation<Void, Never>?
        private var releasing: CheckedContinuation<Void, Never>?

        func pause() async {
            entered = true
            entering?.resume()
            entering = nil
            await withCheckedContinuation { releasing = $0 }
        }

        func waitForEntry() async {
            if entered { return }
            await withCheckedContinuation { entering = $0 }
        }

        func release() {
            releasing?.resume()
            releasing = nil
        }
    }

    @Test func accountSwitchDropsQueuedEventsAndKeepsCapturedIdentity() async {
        let firstUser = UUID()
        let nextUser = UUID()
        var session: UUID? = firstUser
        let first = RecommendationEvent.batch(RecommendationBatch(modelVersion: "first", inputCount: 5))
        let stale = RecommendationEvent.batch(RecommendationBatch(modelVersion: "stale", inputCount: 6))
        let next = RecommendationEvent.batch(RecommendationBatch(modelVersion: "next", inputCount: 7))
        let gate = Gate()
        var delivered: [(RecommendationEvent, UUID)] = []
        let logger = SupabaseRecommendationEventLogger(pipeline: .stars, currentUserID: { session }) { event, userID in
            delivered.append((event, userID))
            if event == first { await gate.pause() }
        }

        logger.log(first)
        await gate.waitForEntry()
        logger.log(stale)
        session = nextUser
        logger.log(next)
        await gate.release()
        await logger.waitForPendingEvents()

        #expect(delivered.map { $0.0 } == [first, next])
        #expect(delivered.map { $0.1 } == [firstUser, nextUser])
    }

    @Test func logoutDropsQueuedEventsAndSignedOutEventsAreIgnored() async {
        let user = UUID()
        var session: UUID? = user
        let first = RecommendationEvent.batch(RecommendationBatch(modelVersion: "first", inputCount: 5))
        let queued = RecommendationEvent.feedback(batchID: UUID(), movieID: 10, verdict: .great)
        let gate = Gate()
        var delivered: [RecommendationEvent] = []
        let logger = SupabaseRecommendationEventLogger(pipeline: .stars, currentUserID: { session }) { event, _ in
            delivered.append(event)
            if event == first { await gate.pause() }
        }

        logger.log(first)
        await gate.waitForEntry()
        logger.log(queued)
        session = nil
        logger.log(queued)
        await gate.release()
        await logger.waitForPendingEvents()

        #expect(delivered == [first])
    }

    @Test func everyPayloadCarriesCapturedUserIDForDatabaseRowSecurity() throws {
        let user = UUID()
        let batch = UUID()
        func json(_ value: some Encodable) throws -> [String: Any] {
            try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        }
        let batchRow = try json(SupabaseRecommendationEventLogger.BatchRow(
            id: batch, pipeline: "stars", modelVersion: "test", inputCount: 5, createdAt: .now, userID: user
        ))
        let impressionRow = try json(SupabaseRecommendationEventLogger.ImpressionRow(
            batchID: batch, movieID: 10, rank: 1, score: nil, shownPosition: 1, userID: user
        ))
        let feedbackRow = try json(SupabaseRecommendationEventLogger.FeedbackRow(
            batchID: batch, movieID: 10, verdict: .great, userID: user
        ))
        for row in [batchRow, impressionRow, feedbackRow] {
            #expect(row["user_id"] as? String == user.uuidString)
        }
        #expect(impressionRow["score"] is NSNull)
    }

    @Test func legacyGreatAndCurrentNeutralRetainDistinctMeaning() throws {
        let oldGreat = Data(#"{"movie_id":101,"signal":"like","rating":3,"source":"onboarding"}"#.utf8)
        let neutral = Data(#"{"movie_id":102,"signal":"neutral","rating":3,"source":"onboarding"}"#.utf8)
        let first = try JSONDecoder().decode(SupabaseTasteSignalService.Row.self, from: oldGreat)
        let second = try JSONDecoder().decode(SupabaseTasteSignalService.Row.self, from: neutral)
        #expect(SupabaseTasteSignalService.signal(from: first)?.verdict == .great)
        #expect(SupabaseTasteSignalService.signal(from: second)?.verdict == .neutral)
    }
}
