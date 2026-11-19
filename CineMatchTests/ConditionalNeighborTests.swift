import Foundation
import Testing
@testable import CineMatch

@MainActor
private func conditionalFixture(_ edit: (inout [String: Any]) -> Void = { _ in }) throws -> ConditionalNeighborRecommender {
    let counts: [Int] = [5, 30, 40, 9000, 10, 100, 100, 1]
    var movies: [[String: Any]] = []
    for index in 0..<8 {
        let title: String = index == 7 ? "The Searchable Film" : "Film \(index + 1)"
        let movie: [String: Any] = [
            "movieLensId": index + 1, "tmdbId": index + 101, "eligible": index != 3,
            "title": title, "year": 2000 + index, "genres": ["Drama"], "trainingCount": counts[index],
        ]
        movies.append(movie)
    }
    let scoring: [String: Any] = [
        "aggregation": "positive", "ratingCenter": 3,
        "fallback": "training_rating_count", "tieBreak": "original_catalogue_order",
    ]
    let legacy: [[String: Int]] = [["letterboxdId": 100001, "tmdbId": 101], ["letterboxdId": 100002, "tmdbId": 101]]
    var json: [String: Any] = [
        "format": "cinematch.conditional-neighbors", "schemaVersion": 1,
        "modelType": "positive_conditional_neighbors", "modelVersion": "conditional-test",
        "sourceModelSHA256": String(repeating: "a", count: 64), "tmdbIdentityVerified": true,
        "scoring": scoring,
        "movies": movies,
        "neighborOffsets": [0, 3, 5, 6, 6, 6, 6, 6, 6],
        "neighborIndices": [1, 2, 3, 2, 4, 0],
        "neighborWeights": [0.25, 0.5, 1.0, 0.25, 0.5, 0.2],
        "legacyMappings": legacy,
    ]
    edit(&json)
    return try ConditionalNeighborRecommender(
        file: JSONDecoder().decode(ConditionalNeighborModelFile.self, from: JSONSerialization.data(withJSONObject: json))
    )
}

@MainActor
struct ConditionalNeighborTests {
    @Test func directedWeightsRatingStrengthAndZeroTailMatchHandCalculation() throws {
        let model = try conditionalFixture()
        let output = try model.recommend(ratings: [.init(tmdbId: 101, stars: 4), .init(tmdbId: 102, stars: 5)], limit: 20)
        #expect(output.results.map(\.tmdbId) == [103, 105, 106, 107, 108])
        #expect(output.results.map(\.score) == [1, 1, 0, 0, 0])
        #expect(output.personalized && output.ratingsUsed == 2 && output.positiveRatingsUsed == 2)
        let reverse = try model.recommend(ratings: [.init(tmdbId: 103, stars: 4)], limit: 1)
        #expect(reverse.results == [.init(tmdbId: 101, score: 0.2)])
    }

    @Test func allSeenVerdictsAreExcludedAndUnknownOrIneligibleIDsNeverEnterGraph() throws {
        let model = try conditionalFixture()
        let output = try model.recommend(
            ratings: [.init(tmdbId: 101, stars: 5), .init(tmdbId: 102, stars: 1),
                      .init(tmdbId: 103, stars: 3), .init(tmdbId: 104, stars: 5), .init(tmdbId: 999, stars: 5)],
            excluding: [105], limit: 20
        )
        #expect(output.results.map(\.tmdbId) == [106, 107, 108])
        #expect(output.results.allSatisfy { $0.score == 0 })
        #expect(output.ratingsUsed == 3 && output.positiveRatingsUsed == 1)
        #expect(output.unknownRatedIDs == [104, 999])
        #expect(model.movie(tmdbId: 104) == nil)
        #expect(model.legacyTMDBID(letterboxdId: 100001) == 101)
        #expect(model.legacyTMDBID(letterboxdId: 100002) == 101)
    }

    @Test func emptyNegativeOnlyAndIsolatedPositiveProfilesUseCountFallback() throws {
        let model = try conditionalFixture()
        let empty = try model.recommend(ratings: [], limit: 20)
        #expect(!empty.personalized)
        #expect(empty.results.map(\.tmdbId) == [106, 107, 103, 102, 105, 101, 108])
        let negative = try model.recommend(ratings: [.init(tmdbId: 101, stars: 1), .init(tmdbId: 103, stars: 3)], limit: 20)
        #expect(!negative.personalized && negative.ratingsUsed == 2)
        #expect(negative.results.map(\.tmdbId) == [106, 107, 102, 105, 108])
        let isolated = try model.recommend(ratings: [.init(tmdbId: 108, stars: 5)], limit: 20)
        #expect(!isolated.personalized && isolated.positiveRatingsUsed == 1)
        #expect(isolated.results.first?.tmdbId == 106)
    }

    @Test func fallbackDecisionPrecedesEligibilityAndExclusions() throws {
        let model = try conditionalFixture {
            $0["neighborOffsets"] = [0, 1, 1, 1, 1, 1, 1, 1, 1]
            $0["neighborIndices"] = [3] // Only an ineligible movie receives a positive score.
            $0["neighborWeights"] = [1.0]
        }
        let output = try model.recommend(ratings: [.init(tmdbId: 101, stars: 4)], limit: 20)
        #expect(output.personalized)
        #expect(output.results.map(\.tmdbId) == [102, 103, 105, 106, 107, 108])
        #expect(output.results.allSatisfy { $0.score == 0 })
    }

    @Test func fractionalRatingsAndMoreThanTwentyFiveSeedsArePreserved() throws {
        let model = try conditionalFixture {
            $0["movies"] = (0..<40).map { index -> [String: Any] in
                ["movieLensId": index + 1, "tmdbId": index + 1000, "eligible": true,
                 "title": "Film \(index)", "year": 2000, "genres": [], "trainingCount": 1]
            }
            $0["neighborOffsets"] = Array(0...39) + [39]
            $0["neighborIndices"] = Array(repeating: 39, count: 39)
            $0["neighborWeights"] = Array(repeating: 0.01, count: 39)
            $0["legacyMappings"] = []
        }
        let output = try model.recommend(ratings: (1000..<1031).map { .init(tmdbId: $0, stars: 3.5) }, limit: 1)
        #expect(output.ratingsUsed == 31)
        #expect(output.results.first?.tmdbId == 1039)
        #expect(abs((output.results.first?.score ?? 0) - 0.155) < 1e-12)
    }

    @Test func invalidInputsAndUnverifiedOrMalformedExportsAreRejected() throws {
        let model = try conditionalFixture()
        #expect(throws: ConditionalNeighborRecommender.InputError.invalidLimit) {
            try model.recommend(ratings: [], limit: 0)
        }
        #expect(throws: ConditionalNeighborRecommender.InputError.duplicateRating(101)) {
            try model.recommend(ratings: [.init(tmdbId: 101, stars: 4), .init(tmdbId: 101, stars: 5)], limit: 5)
        }
        #expect(throws: ConditionalNeighborRecommender.InputError.invalidRating(0)) {
            try model.recommend(ratings: [.init(tmdbId: 101, stars: 0)], limit: 5)
        }
        #expect(throws: ConditionalNeighborRecommender.LoadError.unverifiedCatalogue) {
            try conditionalFixture { $0["tmdbIdentityVerified"] = false }
        }
        #expect(throws: ConditionalNeighborRecommender.LoadError.self) {
            try conditionalFixture { $0["neighborOffsets"] = [0, 3, 2, 6, 6, 6, 6, 6, 6] }
        }
        #expect(throws: ConditionalNeighborRecommender.LoadError.self) {
            try conditionalFixture { $0["neighborIndices"] = [99, 2, 3, 2, 4, 0] }
        }
        #expect(throws: ConditionalNeighborRecommender.LoadError.self) {
            try conditionalFixture {
                var movies = $0["movies"] as! [[String: Any]]
                movies[1]["tmdbId"] = 101
                $0["movies"] = movies
            }
        }
    }
}

@MainActor
struct ConditionalNeighborServiceTests {
    private func opinions(_ extra: [TasteSignal] = []) -> [TasteSignal] {
        [101, 102, 103, 105, 106].map { TasteSignal(movieID: $0, verdict: .great) } + extra
    }

    @Test func swipeSearchAndLookupShareEntireEligibleCatalogue() async throws {
        let model = try conditionalFixture()
        let service = ConditionalNeighborMovieDataService(store: ConditionalNeighborModelStore(preloaded: model))
        let titles = try await service.allTitles()
        #expect(Set(titles.map(\.id)) == model.supportedTMDBIDs)
        #expect(titles.allSatisfy { $0.id == $0.tmdbId })
        #expect(titles.first?.id == 106)
        #expect(try await service.search("searchable").map(\.id) == [108])
        #expect(try await service.search(" \n").isEmpty)
        #expect(try await service.titles(withIDs: [108, 104, 101]).map(\.id) == [108, 101])
    }

    @Test func serviceCountsKnownPositivesPreservesNotSeenAndLogsUsableRatings() async throws {
        let signals = MockTasteSignalService(signals: opinions([
            .init(movieID: 107, verdict: .bad), .init(movieID: 108, verdict: .notSeen),
            .init(movieID: 999, verdict: .fantastic),
        ]))
        let service = ConditionalNeighborRecommendationService(
            store: ConditionalNeighborModelStore(preloaded: try conditionalFixture()), tasteSignalService: signals
        )
        try await service.requestRecompute()
        let result = try await service.latestRecommendations()
        #expect(result.map(\.movieID) == [108])
        #expect(result.first?.reason == "Based on your ratings")
        #expect(await service.latestBatch()?.inputCount == 6)
        #expect(await service.latestBatch()?.modelVersion == "conditional-test")
        await service.clearRecommendations()
        #expect(try await service.latestRecommendations().isEmpty)
        #expect(await service.latestBatch() == nil)
    }

    @Test func unsupportedAndDuplicateLikesCannotPassOnboardingGate() async throws {
        let signals = MockTasteSignalService(signals: [101, 102, 103, 105, 105, 104, 999].map {
            TasteSignal(movieID: $0, verdict: .fantastic)
        })
        let service = ConditionalNeighborRecommendationService(
            store: ConditionalNeighborModelStore(preloaded: try conditionalFixture()), tasteSignalService: signals
        )
        await #expect(throws: RecommendationServiceError.tooFewLikes) { try await service.requestRecompute() }
    }

    @Test func newestVerdictWinsIncludingAChangeToNotSeen() async throws {
        let now = Date()
        let signals = MockTasteSignalService(signals: opinions([
            .init(movieID: 101, verdict: .notSeen, answeredAt: now),
            .init(movieID: 107, verdict: .great, answeredAt: now),
        ]))
        let service = ConditionalNeighborRecommendationService(
            store: ConditionalNeighborModelStore(preloaded: try conditionalFixture()), tasteSignalService: signals
        )
        try await service.requestRecompute()
        #expect(try await service.latestRecommendations().contains { $0.movieID == 101 })
        #expect(await service.latestBatch()?.inputCount == 5)
    }

    @Test func clearingWhileFetchIsSuspendedCannotRepopulateRecommendations() async throws {
        let signals = SuspendedConditionalSignals()
        let service = ConditionalNeighborRecommendationService(
            store: ConditionalNeighborModelStore(preloaded: try conditionalFixture()), tasteSignalService: signals
        )
        let pending = Task { try await service.requestRecompute() }
        await signals.waitForRequests(1)
        await service.clearRecommendations()
        signals.resume(0, with: opinions())
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(try await service.latestRecommendations().isEmpty)
        #expect(await service.latestBatch() == nil)
    }

    @Test func newerRequestWinsEvenWhenOlderRequestCompletesLast() async throws {
        let signals = SuspendedConditionalSignals()
        let service = ConditionalNeighborRecommendationService(
            store: ConditionalNeighborModelStore(preloaded: try conditionalFixture()), tasteSignalService: signals
        )
        let first = Task { try await service.requestRecompute() }
        await signals.waitForRequests(1)
        let second = Task { try await service.requestRecompute() }
        await signals.waitForRequests(2)
        signals.resume(1, with: opinions([.init(movieID: 107, verdict: .bad)]))
        try await second.value
        let newBatch = await service.latestBatch()
        signals.resume(0, with: []) // Would normally clear the result for too few likes.
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(await service.latestBatch() == newBatch)
        #expect(try await service.latestRecommendations().map(\.movieID) == [108])
    }

    @Test func cancelledRequestCannotPublishAfterItsFetchReturns() async throws {
        let signals = SuspendedConditionalSignals()
        let service = ConditionalNeighborRecommendationService(
            store: ConditionalNeighborModelStore(preloaded: try conditionalFixture()), tasteSignalService: signals
        )
        let pending = Task { try await service.requestRecompute() }
        await signals.waitForRequests(1)
        pending.cancel()
        signals.resume(0, with: opinions())
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(try await service.latestRecommendations().isEmpty)
    }
}

@MainActor
private final class SuspendedConditionalSignals: TasteSignalService {
    private var pending: [CheckedContinuation<[TasteSignal], any Error>?] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func allSignals() async throws -> [TasteSignal] {
        try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
            let ready = waiters.filter { pending.count >= $0.0 }
            waiters.removeAll { pending.count >= $0.0 }
            for (_, waiter) in ready { waiter.resume() }
        }
    }

    func waitForRequests(_ count: Int) async {
        if pending.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func resume(_ index: Int, with signals: [TasteSignal]) {
        let continuation = pending[index]
        pending[index] = nil
        continuation?.resume(returning: signals)
    }

    func save(_ signal: TasteSignal) async throws {}
    func deleteSignal(movieID: Int) async throws {}
}
