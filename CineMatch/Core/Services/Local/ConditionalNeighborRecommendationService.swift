import Foundation

/// Applies the app's five-positive onboarding rule, then scores every supported seen opinion.
final class ConditionalNeighborRecommendationService: RecommendationService {
    /// Used when no single liked movie explains the result (e.g. it scored zero).
    static let reasonText = "Based on your ratings"
    /// Used when the user has no positive ratings the model can use, so results are the most-rated movies.
    static let popularReasonText = "Popular with film fans"

    static func becauseText(_ title: String) -> String { "Because you liked \(title)" }
    private let store: ConditionalNeighborModelStore
    private let tasteSignalService: any TasteSignalService
    private let candidateCount: Int
    private var latest: [Recommendation] = []
    private var batch: RecommendationBatch?
    private var generation: UInt64 = 0

    init(store: ConditionalNeighborModelStore, tasteSignalService: any TasteSignalService, candidateCount: Int = 50) {
        self.store = store
        self.tasteSignalService = tasteSignalService
        self.candidateCount = candidateCount
    }

    func requestRecompute() async throws {
        generation &+= 1
        let requestGeneration = generation
        try ensureCurrent(requestGeneration)
        let model: ConditionalNeighborRecommender
        do { model = try await store.recommender() }
        catch {
            try ensureCurrent(requestGeneration)
            discardCurrentResult()
            throw RecommendationServiceError.notReady
        }
        try ensureCurrent(requestGeneration)
        let signals: [TasteSignal]
        do { signals = try await tasteSignalService.allSignals() }
        catch {
            try ensureCurrent(requestGeneration)
            discardCurrentResult()
            if let signalError = error as? TasteSignalServiceError, signalError == .unauthorized {
                throw RecommendationServiceError.unauthorized
            }
            throw RecommendationServiceError.network
        }
        try ensureCurrent(requestGeneration)

        // Services return newest first. Explicit timestamps also protect adapters returning another order.
        let ordered = signals.enumerated().sorted { left, right in
            let leftDate = left.element.answeredAt ?? .distantPast
            let rightDate = right.element.answeredAt ?? .distantPast
            return leftDate != rightDate ? leftDate > rightDate : left.offset < right.offset
        }
        var deduplicated: [Int: TasteSignal] = [:]
        for (_, signal) in ordered where deduplicated[signal.movieID] == nil {
            deduplicated[signal.movieID] = signal
        }
        let supported = deduplicated.values.filter { model.movie(tmdbId: $0.movieID) != nil }
        guard supported.filter(\.verdict.isPositive).count >= TasteInput.minimumCount else {
            discardCurrentResult()
            throw RecommendationServiceError.tooFewLikes
        }
        let seen = supported.filter(\.verdict.isSeen).sorted { $0.movieID < $1.movieID }
        let ratings = seen.map { ConditionalNeighborRecommender.Rating(tmdbId: $0.movieID, stars: Double($0.score)) }
        let output: ConditionalNeighborRecommender.Output
        do {
            output = try model.recommend(
                ratings: ratings,
                excluding: Set(seen.map(\.movieID)),
                limit: candidateCount
            )
        } catch {
            try ensureCurrent(requestGeneration)
            discardCurrentResult()
            throw RecommendationServiceError.unknown
        }
        try ensureCurrent(requestGeneration)
        // "Because you liked …" from the same edge contributions the score is built from.
        let because = output.personalized
            ? model.strongestContributors(to: output.results.map(\.tmdbId), ratings: ratings)
            : [:]
        latest = output.results.enumerated().map { position, result in
            let reason: String
            var becauseMovieID: Int?
            if !output.personalized {
                reason = Self.popularReasonText
            } else if let sourceID = because[result.tmdbId], let title = model.movie(tmdbId: sourceID)?.title {
                reason = Self.becauseText(title)
                becauseMovieID = sourceID
            } else {
                reason = Self.reasonText
            }
            return Recommendation(
                rank: position + 1, movieID: result.tmdbId, score: result.score,
                reason: reason, becauseMovieID: becauseMovieID
            )
        }
        batch = RecommendationBatch(modelVersion: model.modelVersion, inputCount: output.ratingsUsed)
    }

    func latestRecommendations() async throws -> [Recommendation] { latest }
    func latestBatch() async -> RecommendationBatch? { batch }
    func clearRecommendations() async {
        generation &+= 1
        discardCurrentResult()
    }

    private func discardCurrentResult() { latest = []; batch = nil }

    private func ensureCurrent(_ requestGeneration: UInt64) throws {
        guard requestGeneration == generation else { throw CancellationError() }
        try Task.checkCancellation()
    }
}
