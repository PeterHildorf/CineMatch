//
//  RatingRecommendationService.swift
//  CineMatch
//

/// Anbefalinger fra Antons nye model (`RatingRecommender`), regnet lokalt.
///
/// - Input: alle sete film med deres tal (Horrible 1 · Bad 2 · Neutral 3 · Great 4 · Fantastic 5).
/// - "Haven't seen" (0) er ikke input og udelukker ikke filmen.
/// - Film-id er Letterboxd-id, ligesom Antons nuværende model, så Swipe/Search/Today bruger samme data.
/// - Slås til med launch-argumentet `-ratingModel` (se `AppContainer`).
final class RatingRecommendationService: RecommendationService {
    static let fallbackReason = "Based on your ratings"

    private let store: RatingModelStore
    /// Til "Because you liked <titel>".
    private let catalog: ModelStore
    private let tasteSignalService: any TasteSignalService
    private let candidateCount: Int
    private var latest: [Recommendation] = []
    private var batch: RecommendationBatch?

    init(store: RatingModelStore, catalog: ModelStore, tasteSignalService: any TasteSignalService, candidateCount: Int = 50) {
        self.store = store
        self.catalog = catalog
        self.tasteSignalService = tasteSignalService
        self.candidateCount = candidateCount
    }

    func requestRecompute() async throws {
        let signals: [TasteSignal]
        do {
            signals = try await tasteSignalService.allSignals()
        } catch {
            throw RecommendationServiceError.network
        }

        // Samme krav som i dag (nok Great/Fantastic), så onboarding og Today opfører sig ens for begge modeller.
        guard signals.likedMovieIDs.count >= TasteViewModel.minimumLikes else {
            throw RecommendationServiceError.tooFewLikes
        }

        let recommender: RatingRecommender
        do {
            recommender = try await store.recommender()
        } catch {
            throw RecommendationServiceError.notReady
        }

        let ratings = signals
            .filter(\.verdict.isSeen)
            .map { RatingRecommender.Rating(movieID: $0.movieID, score: Double($0.score)) }
        let results = recommender.recommend(ratings: ratings, excluding: signals.seenMovieIDs, limit: candidateCount)

        // Titler til begrundelsen kommer fra kataloget. Mangler det, bruges en generel tekst.
        let titles = try? await catalog.recommender()
        latest = results.enumerated().map { position, result in
            let because = result.becauseMovieID.flatMap { titles?.film(id: $0)?.title }
            return Recommendation(
                rank: position + 1,
                movieID: result.movieID,
                score: result.predicted,   // forudsagt dom (ca. 1–5) – vises ikke som procent
                reason: because.map { "Because you liked \($0)" } ?? Self.fallbackReason
            )
        }
        batch = RecommendationBatch(modelVersion: recommender.modelVersion, inputCount: recommender.usableRatingCount(ratings))
    }

    func latestRecommendations() async throws -> [Recommendation] {
        latest
    }

    func latestBatch() async -> RecommendationBatch? {
        batch
    }

    func clearRecommendations() async {
        latest = []
        batch = nil
    }
}
